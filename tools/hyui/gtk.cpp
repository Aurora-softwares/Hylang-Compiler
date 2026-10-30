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
    QLibrary gtk{"libgtk-4.so.1"}, adw{"libadwaita-1.so.0"}, object{"libgobject-2.0.so.0"}, glib{"libglib-2.0.so.0"}, gio{"libgio-2.0.so.0"}, pixbuf{"libgdk_pixbuf-2.0.so.0"};
public:
    Api() {
        for (QLibrary* library : {&gtk, &adw, &object, &glib, &gio, &pixbuf}) { library->setLoadHints(QLibrary::PreventUnloadHint); }
        if (!gtk.load() || !adw.load() || !object.load() || !glib.load() || !gio.load() || !pixbuf.load()) { throw std::runtime_error("native Linux UI requires the system GTK 4 and libadwaita libraries"); }
    }
    template<class R = void, class... A> R call(const char* name, A... args) {
        QFunctionPointer function = gtk.resolve(name);
        if (!function) { function = adw.resolve(name); }
        if (!function) { function = object.resolve(name); }
        if (!function) { function = glib.resolve(name); }
        if (!function) { function = gio.resolve(name); }
        if (!function) { function = pixbuf.resolve(name); }
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
    std::function<void(W)> itemAction;
    std::function<void(int)> responseAction;
    QVector<W> choices;
    W dialog = nullptr;
};
void factoryThunk(W, W item, W data) { static_cast<Control*>(data)->itemAction(item); }
void responseThunk(W, int response, W data) { static_cast<Control*>(data)->responseAction(response); }
void signalThunk(W, W data) { static_cast<Control*>(data)->action(); }
void notifyThunk(W, W, W data) { static_cast<Control*>(data)->action(); }
int closeThunk(W, W) { QCoreApplication::quit(); return 0; }

class GtkView : public NativeView {
    friend class GtkUiTests;
    Api api;
    const Document& document;
    Bridge& bridge;
    QMap<QString, Control*> controls;
    std::vector<std::unique_ptr<Control>> owned;
    struct Row { W widget; const Node* node; int columns = 1; bool homogeneous = true; };
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
            if (applying || bridge.isApplying() || bridge.state().value(c->node->id + '.' + property) == value) { return; }
            bridge.store(c->node->id, property, value);
            const QString handler = c->node->attributes.value(action);
            if (!handler.isEmpty()) { bridge.dispatch(handler, c->node->id); }
        };
        int minimum = a.value("minimum", "0").toInt(), maximum = a.value("maximum", "100").toInt();
        const QString tag = node.tag;
        if (tag == "State" || tag == "Dialog") { return nullptr; }
        if (tag == "Timer") {
            QTimer* timer = new QTimer(&bridge); timer->setInterval(a.value("interval", "1000").toInt());
            QObject::connect(timer, &QTimer::timeout, &bridge, [this, &node] { bridge.dispatch(node.attributes["onTick"], node.id); });
            timer->setObjectName(node.id); timers.append(timer); return nullptr;
        }
        W w = nullptr;
        if (tag == "MenuBar") {
            w = api.call<W>("gtk_box_new", 0, 8); for (const Node& child : node.children) { append(w, build(child)); }
        } else if (tag == "Menu") {
            w = api.call<W>("gtk_menu_button_new"); W popover = api.call<W>("gtk_popover_new"), box = api.call<W>("gtk_box_new", 1, 4);
            for (const Node& child : node.children) { append(box, build(child)); }
            api.call("gtk_popover_set_child", popover, box); api.call("gtk_menu_button_set_popover", w, popover);
        } else if (tag == "Tabs") {
            w = api.call<W>("gtk_notebook_new"); c->widget = w; api.call("gtk_notebook_set_scrollable", w, 1);
            for (const Node& page : node.children) { api.call<int>("gtk_notebook_append_page", w, build(page), api.call<W>("gtk_label_new", page.attributes.value("title").toUtf8().constData())); }
            connect(c, "notify::page", [this, c, event] { event("value", api.call<int>("gtk_notebook_get_current_page", c->widget), "onChange"); }, true);
        } else if (tag == "RadioGroup") {
            w = api.call<W>("gtk_box_new", 1, 8);
            int index = 0; W first = nullptr;
            for (const QString& label : a.value("items").split('|')) {
                W radio = api.call<W>("gtk_check_button_new_with_label", label.toUtf8().constData());
                if (first) { api.call("gtk_check_button_set_group", radio, first); } else { first = radio; }
                int selected = index++; c->choices.append(radio); append(w, radio);
                Control hook; hook.widget = radio; connect(&hook, "toggled", [this, radio, selected, event] { if (api.call<int>("gtk_check_button_get_active", radio)) { event("value", selected, "onChange"); } });
            }
        } else if (tag == "ListBox") {
            w = api.call<W>("gtk_list_box_new"); c->widget = w; api.call("gtk_list_box_set_selection_mode", w, 2);
            for (const QString& label : a.value("items").split('|')) { W text = api.call<W>("gtk_label_new", label.toUtf8().constData()); api.call("gtk_label_set_xalign", text, 0.0f); api.margin(text, 8); api.call("gtk_list_box_append", w, text); }
            connect(c, "row-selected", [this, c, event] { W row = api.call<W>("gtk_list_box_get_selected_row", c->widget); if (row) { event("value", api.call<int>("gtk_list_box_row_get_index", row), "onChange"); } }, true);
            W scroll = api.call<W>("gtk_scrolled_window_new"); api.call("gtk_scrolled_window_set_child", scroll, w); api.call("gtk_widget_set_size_request", scroll, -1, a.value("height", "160").toInt()); c->container = scroll; return scroll;
        } else if (tag == "Table") {
            QList<QByteArray> rows; std::vector<const char*> strings;
            for (const QString& row : a.value("rows").split('\n')) { rows.append(row.toUtf8()); }
            for (const auto& row : rows) { strings.push_back(row.constData()); } strings.push_back(nullptr);
            W model = api.call<W>("gtk_string_list_new", strings.data()); c->buffer = api.call<W>("gtk_single_selection_new", model);
            w = api.call<W>("gtk_column_view_new", c->buffer); c->widget = w;
            int index = 0;
            for (const QString& heading : a.value("columns").split('|')) {
                int column = index++; W factory = api.call<W>("gtk_signal_list_item_factory_new");
                for (const char* signal : {"setup", "bind"}) {
                    auto hook = std::make_unique<Control>(); bool setup = QByteArray(signal) == "setup";
                    hook->itemAction = [this, column, setup](W item) {
                        if (setup) { W label = api.call<W>("gtk_label_new", ""); api.call("gtk_label_set_xalign", label, 0.0f); api.margin(label, 6); api.call("gtk_list_item_set_child", item, label); }
                        else { QString row = QString::fromUtf8(api.call<const char*>("gtk_string_object_get_string", api.call<W>("gtk_list_item_get_item", item))); api.text(api.call<W>("gtk_list_item_get_child", item), "gtk_label_set_text", row.split('|').value(column)); }
                    };
                    api.call<unsigned long>("g_signal_connect_data", factory, signal, reinterpret_cast<void(*)()>(factoryThunk), hook.get(), nullptr, 0); owned.push_back(std::move(hook));
                }
                W col = api.call<W>("gtk_column_view_column_new", heading.toUtf8().constData(), factory); api.call("gtk_column_view_column_set_expand", col, 1); api.call("gtk_column_view_append_column", w, col); api.call("g_object_unref", col);
            }
            connect(c, "notify::selected", [this, c, event] { unsigned selection = api.call<unsigned>("gtk_single_selection_get_selected", c->buffer); if (selection < 32768) { event("value", int(selection), "onChange"); } }, true);
            W scroll = api.call<W>("gtk_scrolled_window_new"); api.call("gtk_scrolled_window_set_child", scroll, w); api.call("gtk_widget_set_size_request", scroll, -1, a.value("height", "160").toInt()); c->container = scroll; return scroll;
        } else if (tag == "Image") {
            int height = a.value("height", "72").toInt();
            W bitmap = api.call<W>("gdk_pixbuf_new_from_file_at_scale", document.resourcePath(a.value("source")).toUtf8().constData(), -1, height, 1, nullptr);
            if (!bitmap) { throw std::runtime_error("cannot decode image asset"); }
            W texture = api.call<W>("gdk_texture_new_for_pixbuf", bitmap); api.call("g_object_unref", bitmap);
            w = api.call<W>("gtk_image_new_from_paintable", texture); api.call("g_object_unref", texture);
            api.call("gtk_widget_set_size_request", w, -1, height); api.call("gtk_widget_set_halign", w, 3);
        } else if (tag == "RowPanel") {
            // FlowBox reports the largest child's minimum width rather than
            // the sum, so a horizontal row cannot lock a window above its
            // breakpoint. GTK then reflows it during ordinary user resizing.
            w = api.call<W>("gtk_flow_box_new");
            api.call("gtk_flow_box_set_selection_mode", w, 0);
            api.call("gtk_flow_box_set_min_children_per_line", w, 1u);
            api.call("gtk_flow_box_set_max_children_per_line", w, 1u);
            api.call("gtk_flow_box_set_column_spacing", w, a.value("gap", "12").toUInt());
            api.call("gtk_flow_box_set_row_spacing", w, a.value("gap", "12").toUInt());
            bool homogeneous = true;
            for (const auto& child : node.children) {
                W widget = build(child); if (widget) { api.call("gtk_flow_box_insert", w, widget, -1); }
                if (child.tag != "State" && child.tag != "Timer" && child.attributes.value("fill", child.tag == "Button" || child.tag == "Spinner" ? "false" : "true") != "true") { homogeneous = false; }
            }
            rows.append({w, &node, 1, homogeneous});
        } else if (tag == "ColumnPanel" || tag == "Panel" || tag == "Tab") {
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
                if (widget) { api.call("gtk_widget_set_size_request", widget, a.value("minItemWidth", "240").toInt(), -1); api.call("gtk_flow_box_insert", w, widget, -1); }
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
        } else if (tag == "MenuItem" && a.contains("checked")) {
            w = api.call<W>("gtk_check_button_new_with_label", ""); c->widget = w;
            connect(c, "toggled", [this, c, event] { event("checked", api.call<int>("gtk_check_button_get_active", c->widget) != 0, "onClick"); });
        } else if (tag == "Button" || tag == "MenuItem") {
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
            W factory = api.call<W>("gtk_signal_list_item_factory_new");
            for (const char* signal : {"setup", "bind"}) {
                auto hook = std::make_unique<Control>(); bool setup = QByteArray(signal) == "setup";
                hook->itemAction = [this, setup](W item) {
                    if (setup) { W label = api.call<W>("gtk_label_new", ""); api.call("gtk_label_set_ellipsize", label, 3); api.call("gtk_label_set_xalign", label, 0.0f); api.call("gtk_list_item_set_child", item, label); }
                    else { W text = api.call<W>("gtk_list_item_get_item", item); api.text(api.call<W>("gtk_list_item_get_child", item), "gtk_label_set_text", QString::fromUtf8(api.call<const char*>("gtk_string_object_get_string", text))); }
                };
                api.call<unsigned long>("g_signal_connect_data", factory, signal, reinterpret_cast<void(*)()>(factoryThunk), hook.get(), nullptr, 0); owned.push_back(std::move(hook));
            }
            api.call("gtk_drop_down_set_factory", w, factory); api.call("g_object_unref", factory);
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
        if (tag == "Image") { api.call("gtk_widget_set_hexpand", w, 0); }
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
            Control* c = it.value();
            if (c->node->tag == "Dialog") {
                bool open = state.value(it.key() + ".open").toBool();
                if (!open && c->dialog) { api.call("gtk_window_destroy", c->dialog); c->dialog = nullptr; }
                if (open && !c->dialog) {
                    c->dialog = api.call<W>("gtk_message_dialog_new", window, 3, 0, 0, "%s", c->node->attributes.value("title", "Hydrogen").toUtf8().constData());
                    api.call("gtk_message_dialog_format_secondary_text", c->dialog, "%s", state.value(it.key() + ".text").toString().toUtf8().constData());
                    api.text(c->dialog, "gtk_window_set_title", c->node->attributes.value("title", "Hydrogen"));
                    int count = 0; for (const QString& button : c->node->attributes.value("buttons", "OK").split('|')) { api.call<W>("gtk_dialog_add_button", c->dialog, button.toUtf8().constData(), count++); }
                    c->responseAction = [this, c, count](int response) {
                        W dialog = c->dialog; c->dialog = nullptr; if (dialog) { api.call("gtk_window_destroy", dialog); }
                        bridge.store(c->node->id, "open", false); bridge.store(c->node->id, "value", response >= 0 ? response : count - 1);
                        QString handler = c->node->attributes.value("onClose"); if (!handler.isEmpty()) { bridge.dispatch(handler, c->node->id); }
                    };
                    api.call<unsigned long>("g_signal_connect_data", c->dialog, "response", reinterpret_cast<void(*)()>(responseThunk), c, nullptr, 0); api.call("gtk_window_present", c->dialog);
                }
                continue;
            }
            if (!c->widget) { continue; }
            auto value = [&](const QString& property) { return state.value(it.key() + '.' + property); };
            const QString tag = c->node->tag;
            api.call("gtk_widget_set_visible", c->container ? c->container : c->widget, value("visible").toBool() ? 1 : 0);
            api.call("gtk_widget_set_sensitive", c->widget, value("enabled").toBool() ? 1 : 0);
            if (tag == "Label") { api.text(c->widget, "gtk_label_set_text", value("text").toString()); }
            if (tag == "Button" || (tag == "MenuItem" && !c->node->attributes.contains("checked"))) { api.text(c->widget, "gtk_button_set_label", value("text").toString()); }
            if (tag == "Input" && QString::fromUtf8(api.call<const char*>("gtk_editable_get_text", c->widget)) != value("text").toString()) { api.text(c->widget, "gtk_editable_set_text", value("text").toString()); }
            if (tag == "TextArea") {
                char* current = nullptr; api.call("g_object_get", c->buffer, "text", &current, nullptr);
                if (QString::fromUtf8(current) != value("text").toString()) { api.call("gtk_text_buffer_set_text", c->buffer, value("text").toString().toUtf8().constData(), -1); }
                api.call("g_free", current);
            }
            if (tag == "CheckBox" || (tag == "MenuItem" && c->node->attributes.contains("checked"))) { api.text(c->widget, "gtk_check_button_set_label", value("text").toString()); api.call("gtk_check_button_set_active", c->widget, value("checked").toBool() ? 1 : 0); }
            if (tag == "Switch") { api.call("gtk_switch_set_active", c->widget, value("checked").toBool() ? 1 : 0); if (c->label) { api.text(c->label, "gtk_label_set_text", value("text").toString()); } }
            if (tag == "Menu") { api.text(c->widget, "gtk_menu_button_set_label", value("text").toString()); }
            if (tag == "Tabs") { api.call("gtk_notebook_set_current_page", c->widget, value("value").toInt()); }
            if (tag == "ListBox") { api.call("gtk_list_box_select_row", c->widget, api.call<W>("gtk_list_box_get_row_at_index", c->widget, value("value").toInt())); }
            if (tag == "Table") { api.call("gtk_single_selection_set_selected", c->buffer, value("value").toUInt()); }
            if (tag == "RadioGroup") { for (int index = 0; index < c->choices.size(); ++index) { api.call("gtk_check_button_set_active", c->choices[index], index == value("value").toInt() ? 1 : 0); } }
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
    void present(int width, int height) override {
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
    void pump() override {
        for (int i = 0; i < 32; ++i) { if (!api.call<int>("g_main_context_iteration", nullptr, 0)) { break; } }
        api.call("gdk_display_flush", api.call<W>("gdk_display_get_default"));
        for (auto& row : rows) {
            int width = api.call<int>("gtk_widget_get_width", row.widget);
            if (width > 0) {
                int count = 0, minimumSum = 0, largest = 0;
                for (const Node& child : row.node->children) {
                    Control* control = controls.value(child.id, nullptr);
                    W widget = control ? (control->container ? control->container : control->widget) : nullptr;
                    if (!widget || !bridge.state().value(child.id + ".visible").toBool()) { continue; }
                    int minimum = 0, natural = 0; api.call("gtk_widget_measure", widget, 0, -1, &minimum, &natural, nullptr, nullptr);
                    ++count; minimumSum += minimum; largest = qMax(largest, minimum);
                }
                int gap = row.node->attributes.value("gap", "12").toInt();
                // Include FlowBoxChild padding and a small resize margin. The
                // row must collapse before its horizontal minimum is reached.
                int needed = (row.homogeneous ? largest * count : minimumSum) + qMax(0, count - 1) * gap + count * 6 + 12;
                bool horizontal = width >= qMax(row.node->attributes.value("breakpoint", "700").toInt(), needed);
                int columns = horizontal ? qMax(1, count) : 1;
                if (row.columns != columns) {
                    row.columns = columns;
                    if (columns == 1) { api.call("gtk_flow_box_set_min_children_per_line", row.widget, 1u); }
                    api.call("gtk_flow_box_set_max_children_per_line", row.widget, unsigned(columns));
                    api.call("gtk_flow_box_set_min_children_per_line", row.widget, unsigned(columns));
                    api.call("gtk_flow_box_set_homogeneous", row.widget, horizontal && row.homogeneous ? 1 : 0);
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
    bool capture(W captured, const QString& path) {
        W paintable = api.call<W>("gtk_widget_paintable_new", captured);
        W snapshot = api.call<W>("gtk_snapshot_new");
        api.call("gdk_paintable_snapshot", paintable, snapshot, double(api.call<int>("gtk_widget_get_width", captured)), double(api.call<int>("gtk_widget_get_height", captured)));
        W node = api.call<W>("gtk_snapshot_free_to_node", snapshot);
        if (!node) {
            W child = api.call<W>("gtk_widget_get_first_child", captured);
            if (child) { W direct = api.call<W>("gtk_snapshot_new"); api.call("gtk_widget_snapshot_child", captured, child, direct); node = api.call<W>("gtk_snapshot_free_to_node", direct); }
        }
        if (!node) { api.call("g_object_unref", paintable); return false; }
        W renderer = api.call<W>("gtk_native_get_renderer", captured);
        W texture = api.call<W>("gsk_renderer_render_texture", renderer, node, nullptr);
        bool saved = texture && api.call<int>("gdk_texture_save_to_png", texture, path.toUtf8().constData());
        if (texture) { api.call("g_object_unref", texture); }
        api.call("gsk_render_node_unref", node); api.call("g_object_unref", paintable);
        return saved;
    }
    bool screenshot(const QString& path) override { return capture(window, path); }
};

}
int gtkMain(int argc, char** argv) {
    return nativeMain(argc, argv, [](const Document& document, Bridge& bridge) {
        return std::make_unique<GtkView>(document, bridge);
    });
}
}
