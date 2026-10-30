// GTK and libadwaita are loaded from the operating system. No copied style,
// painted widget, or Qt window participates in this renderer. Resolving the C
// ABI at runtime keeps GTK development headers out of the compiler toolchain.
#include "gtk.hpp"
#include "native_runtime.hpp"
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLibrary>
#include <QProcess>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTextStream>
#include <QTimer>
#include <functional>
#include <memory>
#include <stdexcept>

namespace hyui {
namespace {
using W = void*;
class Api {
    QLibrary gtk{"libgtk-4.so.1"}, adw{"libadwaita-1.so.0"}, object{"libgobject-2.0.so.0"}, glib{"libglib-2.0.so.0"}, gio{"libgio-2.0.so.0"};
public:
    Api() {
        for (QLibrary* library : {&gtk, &adw, &object, &glib, &gio}) { library->setLoadHints(QLibrary::PreventUnloadHint); }
        if (!gtk.load() || !adw.load() || !object.load() || !glib.load() || !gio.load()) { throw std::runtime_error("native Linux UI requires the system GTK 4 and libadwaita libraries"); }
    }
    template<class R = void, class... A> R call(const char* name, A... args) {
        QFunctionPointer function = gtk.resolve(name);
        if (!function) { function = adw.resolve(name); }
        if (!function) { function = object.resolve(name); }
        if (!function) { function = glib.resolve(name); }
        if (!function) { function = gio.resolve(name); }
        if (!function) { throw std::runtime_error(std::string("missing native GTK API: ") + name); }
        return reinterpret_cast<R(*)(A...)>(function)(args...);
    }
    void text(W widget, const char* method, const QString& value) { call(method, widget, value.toUtf8().constData()); }
    void css(W widget, const char* style) { call("gtk_widget_add_css_class", widget, style); }
    void margin(W widget, int amount) {
        for (const char* side : {"gtk_widget_set_margin_top", "gtk_widget_set_margin_bottom", "gtk_widget_set_margin_start", "gtk_widget_set_margin_end"}) { call(side, widget, amount); }
    }
};
struct Control {
    W widget = nullptr;
    W container = nullptr;
    W label = nullptr;
    W buffer = nullptr;
    const Node* node = nullptr;
    std::function<void()> action;
};
void signalThunk(W, W data) { static_cast<Control*>(data)->action(); }
void notifyThunk(W, W, W data) { static_cast<Control*>(data)->action(); }
int closeThunk(W, W) { QCoreApplication::quit(); return 0; }

class GtkView : public NativeView {
    Api api;
    const Document& document;
    Bridge& bridge;
    QMap<QString, Control*> controls;
    std::vector<std::unique_ptr<Control>> owned;
    struct Row { W widget; const Node* node; int orientation = 1; bool homogeneous = true; };
    QVector<Row> rows;
    QVector<QTimer*> timers;
    bool applying = false;
    W fittedMonitor = nullptr;
    int fittedWidth = 0, fittedHeight = 0;
public:
    W window = nullptr;
    W application = nullptr;
    W error = nullptr;
    GtkView(const Document& doc, Bridge& backend) : document(doc), bridge(backend) {
        api.call("gtk_init");
        api.call("adw_init");
        const QString theme = doc.window.attributes.value("theme", "system");
        if (theme != "system") {
            W manager = api.call<W>("adw_style_manager_get_default");
            api.call("adw_style_manager_set_color_scheme", manager, theme == "dark" ? 4 : 1);
        }
        application = api.call<W>("adw_application_new", "software.aurora.HydrogenUI", 32);
        if (!api.call<int>("g_application_register", application, nullptr, nullptr)) { throw std::runtime_error("cannot register the native GTK application"); }
        window = api.call<W>("adw_application_window_new", application);
        api.text(window, "gtk_window_set_title", doc.window.attributes.value("title", "Hydrogen"));
        api.call("gtk_window_set_deletable", window, 1);
        api.call("gtk_window_set_resizable", window, 1);
        api.call<unsigned long>("g_signal_connect_data", window, "close-request", reinterpret_cast<void(*)()>(closeThunk), nullptr, nullptr, 0);
        W toolbar = api.call<W>("adw_toolbar_view_new");
        W header = api.call<W>("adw_header_bar_new");
        // The header bar obtains its close/minimise/maximise buttons and their
        // layout from GTK's system settings, including Ubuntu's preferences.
        api.call("adw_toolbar_view_add_top_bar", toolbar, header);
        W scroll = api.call<W>("gtk_scrolled_window_new");
        api.call("gtk_scrolled_window_set_policy", scroll, 2, 1);
        W body = api.call<W>("gtk_box_new", 1, 20);
        api.margin(body, doc.window.attributes.value("padding", "24").toInt());
        for (const auto& node : doc.window.children) { append(body, build(node)); }
        error = api.call<W>("gtk_label_new", "");
        api.call("gtk_label_set_wrap", error, 1);
        api.css(error, "error"); append(body, error);
        api.call("gtk_scrolled_window_set_child", scroll, body);
        api.call("adw_toolbar_view_set_content", toolbar, scroll);
        api.call("adw_application_window_set_content", window, toolbar);
        QObject::connect(&bridge, &Bridge::changed, &bridge, [this] { update(); });
        QObject::connect(&bridge, &Bridge::errorChanged, &bridge, [this] { api.text(error, "gtk_label_set_text", bridge.error()); });
        update();
    }
    void append(W parent, W child) { if (child) { api.call("gtk_box_append", parent, child); } }
    void connect(Control* control, const char* signal, std::function<void()> callback, bool notify = false) {
        auto hook = std::make_unique<Control>(); hook->action = std::move(callback);
        W object = control->buffer ? control->buffer : control->widget;
        auto thunk = notify ? reinterpret_cast<void(*)()>(notifyThunk) : reinterpret_cast<void(*)()>(signalThunk);
        api.call<unsigned long>("g_signal_connect_data", object, signal, thunk, hook.get(), nullptr, 0);
        owned.push_back(std::move(hook));
    }
    W build(const Node& node) {
        const auto& a = node.attributes;
        auto control = std::make_unique<Control>();
        Control* c = control.get(); c->node = &node;
        owned.push_back(std::move(control)); controls[node.id] = c;
        auto value = [&](const QString& property) { return bridge.state().value(node.id + '.' + property); };
        auto event = [this, c](const QString& property, const QVariant& value, const QString& action) {
            if (applying || bridge.isApplying()) { return; }
            bridge.store(c->node->id, property, value);
            const QString handler = c->node->attributes.value(action);
            if (!handler.isEmpty()) { bridge.dispatch(handler, c->node->id); }
        };
        int minimum = a.value("minimum", "0").toInt(), maximum = a.value("maximum", "100").toInt();
        const QString tag = node.tag;
        if (tag == "State") { return nullptr; }
        if (tag == "Timer") {
            QTimer* timer = new QTimer(&bridge); timer->setInterval(a.value("interval", "1000").toInt());
            QObject::connect(timer, &QTimer::timeout, &bridge, [this, &node] { bridge.dispatch(node.attributes["onTick"], node.id); });
            timer->setObjectName(node.id); timers.append(timer); return nullptr;
        }
        W w = nullptr;
        if (tag == "ColumnPanel" || tag == "RowPanel" || tag == "Panel") {
            W box = api.call<W>("gtk_box_new", 1, a.value("gap", "12").toInt());
            w = box;
            if (tag == "Panel") {
                w = api.call<W>("gtk_frame_new", nullptr);
                api.css(w, "card"); api.margin(box, a.value("padding", "20").toInt());
                api.call("gtk_frame_set_child", w, box);
                if (a.contains("title")) {
                    W title = api.call<W>("gtk_label_new", a["title"].toUtf8().constData());
                    api.call("gtk_label_set_xalign", title, 0.0f); api.css(title, "heading"); append(box, title);
                }
            }
            for (const auto& child : node.children) { append(box, build(child)); }
            if (tag == "RowPanel") {
                bool homogeneous = true;
                for (const auto& child : node.children) {
                    if (child.tag != "State" && child.tag != "Timer" && child.attributes.value("fill", child.tag == "Button" || child.tag == "Spinner" ? "false" : "true") != "true") { homogeneous = false; }
                }
                rows.append({box, &node, 1, homogeneous});
            }
        } else if (tag == "GridPanel") {
            w = api.call<W>("gtk_flow_box_new");
            api.call("gtk_flow_box_set_selection_mode", w, 0);
            api.call("gtk_flow_box_set_min_children_per_line", w, 1u);
            api.call("gtk_flow_box_set_max_children_per_line", w, a.value("columns", "3").toUInt());
            api.call("gtk_flow_box_set_column_spacing", w, a.value("gap", "16").toUInt());
            api.call("gtk_flow_box_set_row_spacing", w, a.value("gap", "16").toUInt());
            api.call("gtk_flow_box_set_homogeneous", w, 1);
            for (const auto& child : node.children) {
                W widget = build(child);
                if (widget) { api.call("gtk_flow_box_insert", w, widget, -1); }
            }
        } else if (tag == "Label") {
            w = api.call<W>("gtk_label_new", "");
            api.call("gtk_label_set_wrap", w, 1); api.call("gtk_label_set_wrap_mode", w, 2);
            api.call("gtk_label_set_xalign", w, 0.0f);
            QString role = a.value("role");
            if (role == "title") { api.css(w, "title-1"); }
            if (role == "heading") { api.css(w, "title-3"); }
            if (role == "caption") { api.css(w, "caption"); }
            if (a.value("tone") == "muted") { api.css(w, "dim-label"); }
            if (a.value("tone") == "accent") { api.css(w, "accent"); }
        } else if (tag == "Button") {
            w = api.call<W>("gtk_button_new_with_label", ""); c->widget = w;
            if (a.value("primary") == "true") { api.css(w, "suggested-action"); }
            connect(c, "clicked", [this, c] { QString handler = c->node->attributes.value("onClick"); if (!handler.isEmpty()) { bridge.dispatch(handler, c->node->id); } });
        } else if (tag == "Input") {
            w = api.call<W>("gtk_entry_new"); c->widget = w;
            api.text(w, "gtk_entry_set_placeholder_text", a.value("placeholder"));
            connect(c, "changed", [this, c, event] { event("text", QString::fromUtf8(api.call<const char*>("gtk_editable_get_text", c->widget)), "onChange"); });
            connect(c, "activate", [this, c] { QString handler = c->node->attributes.value("onSubmit"); if (!handler.isEmpty()) { bridge.dispatch(handler, c->node->id); } });
        } else if (tag == "TextArea") {
            w = api.call<W>("gtk_text_view_new"); c->widget = w;
            c->buffer = api.call<W>("gtk_text_view_get_buffer", w);
            api.call("gtk_text_view_set_wrap_mode", w, 3);
            api.call("gtk_widget_set_size_request", w, -1, a.value("height", "100").toInt());
            connect(c, "changed", [this, c, event] {
                // GtkTextIter is opaque; GTK exposes text through a GObject
                // property, which avoids depending on its struct layout.
                char* text = nullptr;
                api.call("g_object_get", c->buffer, "text", &text, nullptr);
                event("text", QString::fromUtf8(text), "onChange"); api.call("g_free", text);
            });
        } else if (tag == "CheckBox" || tag == "Switch") {
            w = tag == "CheckBox" ? api.call<W>("gtk_check_button_new_with_label", "") : api.call<W>("gtk_switch_new"); c->widget = w;
            connect(c, tag == "Switch" ? "notify::active" : "toggled", [this, c, event] {
                bool checked = api.call<int>(c->node->tag == "Switch" ? "gtk_switch_get_active" : "gtk_check_button_get_active", c->widget) != 0;
                event("checked", checked, "onChange");
            }, tag == "Switch");
        } else if (tag == "Select") {
            QList<QByteArray> items; std::vector<const char*> strings;
            for (const auto& item : a.value("items").split('|')) { items.append(item.toUtf8()); }
            for (const auto& item : items) { strings.push_back(item.constData()); } strings.push_back(nullptr);
            w = api.call<W>("gtk_drop_down_new_from_strings", strings.data()); c->widget = w;
            connect(c, "notify::selected", [this, c, event] { event("value", api.call<unsigned>("gtk_drop_down_get_selected", c->widget), "onChange"); }, true);
        } else if (tag == "Slider" || tag == "NumberInput") {
            w = tag == "Slider" ? api.call<W>("gtk_scale_new_with_range", 0, double(minimum), double(maximum), 1.0) : api.call<W>("gtk_spin_button_new_with_range", double(minimum), double(maximum), 1.0); c->widget = w;
            if (tag == "Slider") { api.call("gtk_scale_set_draw_value", w, 0); }
            connect(c, "value-changed", [this, c, event] { event("value", int(api.call<double>(c->node->tag == "Slider" ? "gtk_range_get_value" : "gtk_spin_button_get_value", c->widget)), "onChange"); });
        } else if (tag == "ProgressBar") { w = api.call<W>("gtk_progress_bar_new"); }
        else if (tag == "Spinner") { w = api.call<W>("gtk_spinner_new"); }
        else if (tag == "Separator") { w = api.call<W>("gtk_separator_new", 0); }
        else if (tag == "Spacer") { w = api.call<W>("gtk_box_new", 1, 0); api.call("gtk_widget_set_size_request", w, -1, a.value("height", "12").toInt()); }
        if (!w) { return nullptr; }
        c->widget = w;
        if (a.contains("accessibleName")) { api.call("gtk_accessible_update_property", w, 4, a["accessibleName"].toUtf8().constData(), -1); }
        api.call("gtk_widget_set_hexpand", w, a.value("fill", tag == "Button" || tag == "Spinner" ? "false" : "true") == "true" ? 1 : 0);
        api.call("gtk_widget_set_valign", w, 1);
        // A GtkSwitch has no text property: use an ordinary native label beside
        // the actual switch, rather than drawing a simulated toggle.
        if (tag == "Switch") {
            W row = api.call<W>("gtk_box_new", 0, 12);
            W label = api.call<W>("gtk_label_new", value("text").toString().toUtf8().constData());
            api.call("gtk_label_set_wrap", label, 1); api.call("gtk_label_set_wrap_mode", label, 2);
            api.call("gtk_widget_set_hexpand", w, 0); api.call("gtk_widget_set_halign", w, 1);
            c->container = row; c->label = label;
            append(row, w); append(row, label); return row;
        }
        return w;
    }
    void update() {
        applying = true;
        QVariantMap state = bridge.state();
        for (auto it = controls.cbegin(); it != controls.cend(); ++it) {
            Control* c = it.value(); if (!c->widget) { continue; }
            auto value = [&](const QString& property) { return state.value(it.key() + '.' + property); };
            const QString tag = c->node->tag;
            api.call("gtk_widget_set_visible", c->container ? c->container : c->widget, value("visible").toBool() ? 1 : 0);
            api.call("gtk_widget_set_sensitive", c->widget, value("enabled").toBool() ? 1 : 0);
            if (tag == "Label") { api.text(c->widget, "gtk_label_set_text", value("text").toString()); }
            if (tag == "Button") { api.text(c->widget, "gtk_button_set_label", value("text").toString()); }
            if (tag == "Input" && QString::fromUtf8(api.call<const char*>("gtk_editable_get_text", c->widget)) != value("text").toString()) { api.text(c->widget, "gtk_editable_set_text", value("text").toString()); }
            if (tag == "TextArea") {
                char* current = nullptr; api.call("g_object_get", c->buffer, "text", &current, nullptr);
                if (QString::fromUtf8(current) != value("text").toString()) { api.call("gtk_text_buffer_set_text", c->buffer, value("text").toString().toUtf8().constData(), -1); }
                api.call("g_free", current);
            }
            if (tag == "CheckBox") { api.text(c->widget, "gtk_check_button_set_label", value("text").toString()); api.call("gtk_check_button_set_active", c->widget, value("checked").toBool() ? 1 : 0); }
            if (tag == "Switch") { api.call("gtk_switch_set_active", c->widget, value("checked").toBool() ? 1 : 0); if (c->label) { api.text(c->label, "gtk_label_set_text", value("text").toString()); } }
            if (tag == "Select") { api.call("gtk_drop_down_set_selected", c->widget, value("value").toUInt()); }
            if (tag == "Slider" || tag == "NumberInput") { api.call(tag == "Slider" ? "gtk_range_set_value" : "gtk_spin_button_set_value", c->widget, value("value").toDouble()); }
            if (tag == "ProgressBar") {
                auto range = document.ranges.value(it.key(), qMakePair(0, 100));
                double fraction = range.second == range.first ? 0 : (value("value").toDouble() - range.first) / (range.second - range.first);
                api.call("gtk_progress_bar_set_fraction", c->widget, fraction);
            }
            if (tag == "Spinner") { api.call(value("running").toBool() ? "gtk_spinner_start" : "gtk_spinner_stop", c->widget); }
        }
        for (QTimer* timer : timers) { bool run = state.value(timer->objectName() + ".running").toBool(); if (run && !timer->isActive()) { timer->start(); } if (!run) { timer->stop(); } }
        applying = false;
    }
    void present(int width, int height) {
        struct Rect { int x, y, width, height; } area{};
        W display = api.call<W>("gdk_display_get_default");
        W monitors = api.call<W>("gdk_display_get_monitors", display);
        if (api.call<unsigned>("g_list_model_get_n_items", monitors)) {
            W monitor = api.call<W>("g_list_model_get_item", monitors, 0u);
            api.call("gdk_monitor_get_geometry", monitor, &area); api.call("g_object_unref", monitor);
            width = qMin(width, area.width - 32); height = qMin(height, area.height - 64);
        }
        api.call("gtk_window_set_default_size", window, qMax(200, width), qMax(200, height));
        api.call("gtk_window_present", window);
    }
    void pump() {
        for (int i = 0; i < 32; ++i) { if (!api.call<int>("g_main_context_iteration", nullptr, 0)) { break; } }
        api.call("gdk_display_flush", api.call<W>("gdk_display_get_default"));
        for (auto& row : rows) {
            int width = api.call<int>("gtk_widget_get_width", row.widget);
            if (width > 0) {
                bool horizontal = width >= row.node->attributes.value("breakpoint", "700").toInt();
                int orientation = horizontal ? 0 : 1;
                if (row.orientation != orientation) {
                    row.orientation = orientation;
                    api.call("gtk_orientable_set_orientation", row.widget, orientation);
                    api.call("gtk_box_set_homogeneous", row.widget, horizontal && row.homogeneous ? 1 : 0);
                }
            }
        }
        W surface = api.call<W>("gtk_native_get_surface", window);
        if (surface) {
            W display = api.call<W>("gdk_surface_get_display", surface);
            W monitor = api.call<W>("gdk_display_get_monitor_at_surface", display, surface);
            if (monitor) {
                struct Rect { int x, y, width, height; } area{};
                api.call("gdk_monitor_get_geometry", monitor, &area);
                if (area.width > 0 && area.height > 0 && (monitor != fittedMonitor || area.width != fittedWidth || area.height != fittedHeight)) {
                    fittedMonitor = monitor; fittedWidth = area.width; fittedHeight = area.height;
                    int width = api.call<int>("gtk_widget_get_width", window), height = api.call<int>("gtk_widget_get_height", window);
                    if (width > area.width || height > area.height) { api.call("gtk_window_set_default_size", window, qMin(width, area.width - 32), qMin(height, area.height - 64)); }
                }
            }
        }
        for (auto it = controls.cbegin(); it != controls.cend(); ++it) {
            if (it.value()->node->tag == "ProgressBar" && bridge.state().value(it.key() + ".indeterminate").toBool()) { api.call("gtk_progress_bar_pulse", it.value()->widget); }
        }
    }
    bool screenshot(const QString& path) {
        W paintable = api.call<W>("gtk_widget_paintable_new", window);
        W snapshot = api.call<W>("gtk_snapshot_new");
        api.call("gdk_paintable_snapshot", paintable, snapshot, double(api.call<int>("gtk_widget_get_width", window)), double(api.call<int>("gtk_widget_get_height", window)));
        W node = api.call<W>("gtk_snapshot_free_to_node", snapshot);
        if (!node) {
            W child = api.call<W>("gtk_widget_get_first_child", window);
            if (child) { W direct = api.call<W>("gtk_snapshot_new"); api.call("gtk_widget_snapshot_child", window, child, direct); node = api.call<W>("gtk_snapshot_free_to_node", direct); }
        }
        if (!node) { api.call("g_object_unref", paintable); return false; }
        W renderer = api.call<W>("gtk_native_get_renderer", window);
        W texture = api.call<W>("gsk_renderer_render_texture", renderer, node, nullptr);
        bool saved = texture && api.call<int>("gdk_texture_save_to_png", texture, path.toUtf8().constData());
        if (texture) { api.call("g_object_unref", texture); }
        api.call("gsk_render_node_unref", node); api.call("g_object_unref", paintable);
        return saved;
    }
};

}
int gtkMain(int argc, char** argv) {
    return nativeMain(argc, argv, [](const Document& document, Bridge& bridge) {
        return std::make_unique<GtkView>(document, bridge);
    });
}
}
