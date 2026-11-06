// Include the production renderer so the test can inspect its private native
// GTK objects through a friend, without adding test APIs to the shipping host.
#include "gtk.cpp"
#include <QElapsedTimer>
#include <QThread>
#include <QJsonArray>
#include <iostream>
namespace hyui { namespace {
class GtkUiTests {
    GtkView& view;
    Bridge& bridge;
    QString output;
    QJsonArray screenshots, captures;
    struct Rect { float x, y, width, height; };
    static void check(bool pass, const QString& message) { if (!pass) { throw std::runtime_error(message.toStdString()); } }
    W widget(const QString& id) { check(view.controls.contains(id), "Missing control: " + id); auto c = view.controls[id]; return c->container ? c->container : c->widget; }
    Rect bounds(W child, W parent = nullptr) {
        Rect result{}; check(view.api.call<int>("gtk_widget_compute_bounds", child, parent ? parent : view.window, &result), "Cannot obtain native bounds"); return result;
    }
    void settle(int ms = 200) { QElapsedTimer time; time.start(); while (time.elapsed() < ms) { QCoreApplication::processEvents(); view.pump(); QThread::msleep(2); } }
    template<class F> void until(F predicate, const QString& message, int timeout = 8000) {
        QElapsedTimer time; time.start(); while (!predicate() && time.elapsed() < timeout) { settle(10); }
        check(predicate(), message + ": " + bridge.error()); check(bridge.error().isEmpty(), bridge.error());
    }
    void idle() { settle(50); until([&] { return !bridge.busy(); }, "Backend event timed out"); }
    void click(const QString& id) {
        if (id == "showPopover") { view.api.call("gtk_menu_button_popup", view.controls[id]->widget); }
        else { view.api.call("g_signal_emit_by_name", view.controls[id]->widget, "clicked"); }
        idle();
    }
    void layout() {
        for (auto c : view.controls) {
            const QString tag = c->node->tag;
            if (!(tag == "Panel" || tag == "ColumnPanel" || tag == "RowPanel" || tag == "GridPanel" || tag == "Tab") || !c->widget || !view.api.call<int>("gtk_widget_get_mapped", c->widget)) { continue; }
            W parent = tag == "Panel" ? view.api.call<W>("gtk_frame_get_child", c->widget) : c->widget;
            QVector<Rect> rectangles;
            for (const Node& node : c->node->children) {
                W child = widget(node.id); if (!child || !view.api.call<int>("gtk_widget_get_mapped", child)) { continue; }
                auto rect = bounds(child, parent); if (rect.width <= 0 || rect.height <= 0) { continue; }
                int width = view.api.call<int>("gtk_widget_get_width", parent), height = view.api.call<int>("gtk_widget_get_height", parent);
                check(rect.x >= -1 && rect.x + rect.width <= width + 1, "Horizontal clipping in " + c->node->id + "/" + node.id);
                check(rect.y >= -1 && rect.y + rect.height <= height + 1, "Vertical clipping in " + c->node->id + "/" + node.id);
                for (auto other : rectangles) { check(qMin(rect.x + rect.width, other.x + other.width) - qMax(rect.x, other.x) < 1 || qMin(rect.y + rect.height, other.y + other.height) - qMax(rect.y, other.y) < 1, "Overlapping native GTK controls in " + c->node->id); }
                rectangles.append(rect);
            }
        }
    }
    void capture(const QString& name, W captured = nullptr) {
        view.api.call("gtk_window_set_focus", view.window, nullptr); settle(); check(view.capture(captured ? captured : view.window, output + '/' + name), "GTK screenshot failed: " + name); screenshots.append(name);
        QJsonObject geometry;
        for (auto it = view.controls.cbegin(); it != view.controls.cend(); ++it) {
            W child = widget(it.key()); if (!child || !view.api.call<int>("gtk_widget_get_mapped", child)) { continue; }
            auto rect = bounds(child); geometry[it.key()] = QJsonObject{{"x", rect.x}, {"y", rect.y}, {"width", rect.width}, {"height", rect.height}};
        }
        captures.append(QJsonObject{{"name", name}, {"controls", geometry}});
    }
public:
    GtkUiTests(GtkView& v, Bridge& b, QString directory) : view(v), bridge(b), output(directory) {}
    void run() {
        QDir().mkpath(output);
        for (int page : {0, 1}) {
            view.api.text(view.controls["pages"]->buffer, "gtk_stack_set_visible_child_name", QString::number(page)); idle();
            for (int width : {1120, 800, 360}) {
                view.present(width, 600); settle(350); layout();
                int actualWidth = view.api.call<int>("gtk_widget_get_width", view.window);
                if (actualWidth > width + 2) {
                    for (auto c : view.controls) {
                        if (!c->widget) continue; int minimum = 0, natural = 0;
                        view.api.call("gtk_widget_measure", c->widget, 0, -1, &minimum, &natural, nullptr, nullptr);
                        if (minimum > 200) { std::cerr << "GTK minimum width " << c->node->tag.toStdString() << " " << c->node->id.toStdString() << " = " << minimum << " (natural " << natural << ")\n"; }
                    }
                    check(false, QString("Native window cannot shrink: requested %1, actual %2").arg(width).arg(actualWidth));
                }
                if (page == 0) {
                    auto project = bounds(widget("projectName")), summary = bounds(widget("summary"));
                    if (width == 1120) { check(summary.x > project.x + project.width, "Wide panels must be side by side"); }
                    if (width == 360) {
                        check(summary.y > project.y + project.height, "Narrow panels must stack");
                        check(bounds(widget("workers")).y > bounds(widget("target")).y + bounds(widget("target")).height, "Nested row must stack");
                    }
                } else {
                    auto logo = bounds(widget("logo")), choices = bounds(widget("channel"));
                    check(choices.y - logo.y - logo.height <= 64, "Image must not reserve an oversized empty slot");
                }
                capture(QString("%1-%2.png").arg(page ? "gallery" : "workspace").arg(width));
                if ((page == 0 && width == 1120) || (page == 1 && width == 360)) {
                    W scroller = view.api.call<W>("gtk_widget_get_ancestor", widget(page ? "showDialog" : "status"), view.api.call<unsigned long>("gtk_scrolled_window_get_type"));
                    // Row viewports suppress horizontal minimum-width feedback;
                    // the outer, vertically scrolling document owns this shot.
                    while (scroller) {
                        int horizontal = 0, vertical = 0;
                        view.api.call("gtk_scrolled_window_get_policy", scroller, &horizontal, &vertical);
                        if (vertical == 0 || vertical == 1) { break; }
                        scroller = view.api.call<W>("gtk_widget_get_ancestor", view.api.call<W>("gtk_widget_get_parent", scroller), view.api.call<unsigned long>("gtk_scrolled_window_get_type"));
                    }
                    check(scroller != nullptr, "Missing vertically scrolling document");
                    W adjustment = view.api.call<W>("gtk_scrolled_window_get_vadjustment", scroller);
                    double bottom = view.api.call<double>("gtk_adjustment_get_upper", adjustment) - view.api.call<double>("gtk_adjustment_get_page_size", adjustment);
                    check(bottom > 0, "Document must overflow the short viewport");
                    view.api.call("gtk_adjustment_set_value", adjustment, bottom); settle();
                    check(view.api.call<double>("gtk_adjustment_get_value", adjustment) > 0, "Document failed to scroll");
                    auto lastControl = bounds(widget(page ? "dialogResult" : "save"));
                    check(lastControl.y >= 0 && lastControl.y + lastControl.height <= view.api.call<int>("gtk_widget_get_height", view.window), "Scrolling to the end must reveal the final controls");
                    capture(page ? "gallery-bottom.png" : "workspace-bottom.png");
                    view.api.call("gtk_adjustment_set_value", adjustment, 0.0);
                }
            }
        }
        view.present(1120, 600); settle();
        check(view.api.call<int>("gtk_widget_get_height", view.controls["logo"]->widget) == 80, "Image must honor its declared height");
        W toggle = view.controls["featureToggle"]->widget;
        check(view.api.call<int>("g_type_check_instance_is_a", toggle,
            view.api.call<unsigned long>("gtk_toggle_button_get_type")), "ToggleButton must use GtkToggleButton");
        W validation = view.controls["validationHint"]->widget;
        check(view.api.call<int>("g_type_check_instance_is_a", validation,
            view.api.call<unsigned long>("gtk_label_get_type")), "ValidationMessage must use GtkLabel");
        view.api.call("gtk_toggle_button_set_active", toggle, 1); idle();
        check(bridge.state()["featureToggle.checked"].toBool() &&
              bridge.state()["validationHint.text"].toString() == "Optional features enabled.",
              "ToggleButton change did not reach Hydrogen");
        check(bridge.apply("HYUI\tSET\tfeatureToggle\tchecked\tfalse\nHYUI\tSET\tvalidationHint\ttext\tReset by Hydrogen\n"),
              "Cannot update native toggle and validation feedback");
        check(!view.api.call<int>("gtk_toggle_button_get_active", toggle) &&
              QString::fromUtf8(view.api.call<const char*>("gtk_label_get_text", validation)) == "Reset by Hydrogen",
              "Native toggle and validation state did not update");
        W split = view.controls["ideSplit"]->widget;
        W status = view.controls["ideStatus"]->widget;
        check(view.api.call<int>("g_type_check_instance_is_a", split,
            view.api.call<unsigned long>("gtk_paned_get_type")), "SplitView must use a native GtkPaned");
        check(view.api.call<int>("g_type_check_instance_is_a", status,
            view.api.call<unsigned long>("gtk_label_get_type")), "StatusBar must use a native GtkLabel");
        check(view.api.call<W>("gtk_paned_get_start_child", split) != nullptr &&
              view.api.call<W>("gtk_paned_get_end_child", split) != nullptr,
              "SplitView must hold both panes");
        check(bridge.apply("HYUI\tSET\tideSplit\tvisible\ttrue\nHYUI\tSET\tideStatus\tvisible\ttrue\nHYUI\tSET\tideSplit\tvalue\t300\nHYUI\tSET\tideStatus\ttext\tStatus updated\n"),
              "Cannot update SplitView or StatusBar from Hydrogen");
        settle();
        check(view.api.call<int>("gtk_paned_get_position", split) == 300 &&
              QString::fromUtf8(view.api.call<const char*>("gtk_label_get_text", status)) == "Status updated",
              "Native split divider or status text did not update");
        view.api.call("gtk_paned_set_position", split, 325); idle();
        check(bridge.state()["ideSplit.value"].toInt() == 325 &&
              bridge.state()["ideStatus.text"] == "Navigator width: 325 px",
              "Native split drag did not propagate through Hydrogen");
        W logo = view.api.call<W>("gtk_picture_get_paintable", view.controls["logo"]->widget);
        check(logo != nullptr && view.api.call<int>("gdk_paintable_get_intrinsic_height", logo) == 80, "Bundled image must decode at its declared display size");
        view.api.call("gtk_check_button_set_active", view.controls["channel"]->choices[1], 1); idle();
        check(bridge.state()["channelText.text"] == "Preview channel selected.", "Radio event did not reach Hydrogen");
        view.api.call("gtk_list_box_select_row", view.controls["templates"]->widget, view.api.call<W>("gtk_list_box_get_row_at_index", view.controls["templates"]->widget, 2)); idle();
        check(bridge.state()["selectionText.text"] == "Template index: 2", "List selection did not reach Hydrogen");
        W toolbarCommand = view.controls["toolbarWorkspace"]->widget;
        check(view.api.call<int>("gtk_widget_get_visible", toolbarCommand) &&
              view.api.call<W>("gtk_widget_get_ancestor", toolbarCommand, view.api.call<unsigned long>("adw_header_bar_get_type")) != nullptr,
              "Native libadwaita toolbar command is missing");
        check(bridge.apply("HYUI\tSET\tstudioToolbar\tenabled\tfalse\n"), "Cannot disable native toolbar");
        check(!view.api.call<int>("gtk_widget_is_sensitive", toolbarCommand), "Disabled toolbar left a command active");
        check(bridge.apply("HYUI\tSET\tstudioToolbar\tenabled\ttrue\n"), "Cannot restore native toolbar");
        click("toolbarWorkspace");
        check(bridge.state()["pages.value"].toInt() == 0, "Toolbar workspace command did not reach Hydrogen");
        click("toolbarControls");
        check(bridge.state()["pages.value"].toInt() == 1, "Toolbar gallery command did not reach Hydrogen");
        click("showPopover");
        W tip = view.controls["templateTip"]->dialog;
        check(view.api.call<int>("g_type_check_instance_is_a", view.controls["showPopover"]->widget,
                  view.api.call<unsigned long>("gtk_menu_button_get_type")), "Popover anchor must be a native GtkMenuButton");
        check(tip && view.api.call<int>("g_type_check_instance_is_a", tip, view.api.call<unsigned long>("gtk_popover_get_type")) &&
              view.api.call<int>("gtk_widget_get_visible", tip),
              QString("Native GTK popover did not open: state=%1 mapped=%2 active=%3")
                  .arg(bridge.state()["templateTip.open"].toBool())
                  .arg(view.api.call<int>("gtk_widget_get_mapped", view.controls["showPopover"]->widget))
                  .arg(view.api.call<int>("gtk_menu_button_get_active", view.controls["showPopover"]->widget)));
        check(bridge.apply("HYUI\tSET\ttemplateTip\ttext\tUpdated template tip\n"), "Cannot update popover text");
        check(QString::fromUtf8(view.api.call<const char*>("gtk_label_get_text", view.controls["templateTip"]->label)) == "Updated template tip", "Popover text did not update");
        view.api.call("gtk_popover_popdown", tip); idle();
        check(!bridge.state()["templateTip.open"].toBool() && bridge.state()["selectionText.text"] == "Template tip dismissed.", "Popover dismissal did not reach Hydrogen");
        W context = view.controls["templateContext"]->dialog;
        check(context && view.api.call<int>("g_type_check_instance_is_a", context, view.api.call<unsigned long>("gtk_popover_get_type")), "ContextMenu must use a native GtkPopover");
        view.api.call("g_signal_emit_by_name", view.controls["templateContext"]->buffer, "pressed", 1, 12.0, 12.0); settle();
        check(view.api.call<int>("gtk_widget_get_visible", context), "Right-click did not open the context menu");
        click("inspectTemplate");
        check(bridge.state()["selectionText.text"] == "Inspect template index: 2", "Context menu command did not reach Hydrogen");
        view.api.call("gtk_popover_popdown", context);
        check(!view.controls["templateContext"]->keyAction('x', 0) && view.controls["templateContext"]->keyAction(0xffc7u, 1u), "Menu-key gesture did not reopen the context menu");
        view.api.call("gtk_popover_popdown", context);
        click("copyPreview");
        check(bridge.state()["studioClipboard.value"] == "Inspect template index: 2", "Clipboard write did not update Hydrogen state");
        click("pastePreview");
        until([&] { return bridge.state()["selectionText.text"] == "Clipboard: Inspect template index: 2"; }, "Native GTK clipboard read did not reach Hydrogen");
        W search = view.controls["templateSearch"]->widget;
        check(view.api.call<int>("g_type_check_instance_is_a", search, view.api.call<unsigned long>("gtk_search_entry_get_type")), "SearchInput must use GtkSearchEntry");
        check(view.api.call<int>("gtk_widget_get_visible", search), "Hydrogen did not reveal SearchInput");
        check(QString::fromUtf8(view.api.call<const char*>("gtk_widget_get_tooltip_text", search)) == "Enter a template search term", "Native search tooltip is missing");
        view.api.text(search, "gtk_editable_set_text", "café"); idle();
        check(bridge.state()["selectionText.text"] == "Template search: café", "SearchInput text event did not reach Hydrogen");
        W password = view.controls["templatePassword"]->widget;
        check(view.api.call<int>("g_type_check_instance_is_a", password, view.api.call<unsigned long>("gtk_password_entry_get_type")), "PasswordInput must use GtkPasswordEntry");
        check(view.api.call<int>("gtk_widget_get_visible", password), "Hydrogen did not reveal PasswordInput");
        view.api.text(password, "gtk_editable_set_text", "gallery-pass"); idle();
        check(bridge.state()["selectionText.text"] == "Private code length: 12", "PasswordInput change event failed");
        view.api.call("g_signal_emit_by_name", password, "activate"); idle();
        check(bridge.state()["selectionText.text"] == "Private code accepted.", "PasswordInput did not reach Hydrogen");
        check(!bridge.state().contains("templatePassword.text") && !bridge.state().contains("templatePassword.value"), "Password leaked into UI state");
        check(bridge.apply("HYUI\tSET\ttemplatePassword\tenabled\tfalse\nHYUI\tSET\ttemplatePassword\tvisible\tfalse\n"), "Cannot disable or hide PasswordInput");
        check(!view.api.call<int>("gtk_widget_is_sensitive", password) && !view.api.call<int>("gtk_widget_get_visible", password), "PasswordInput did not apply visibility or enabled state");
        check(bridge.apply("HYUI\tSET\ttemplatePassword\tenabled\ttrue\nHYUI\tSET\ttemplatePassword\tvisible\ttrue\n"), "Cannot restore PasswordInput");
        for (const auto& pickerCase : {qMakePair(QString("openDocument"), 0), qMakePair(QString("saveDocument"), 1), qMakePair(QString("chooseFolder"), 2)}) {
            W picker = view.controls[pickerCase.first]->widget;
            check(view.api.call<int>("g_type_check_instance_is_a", picker, view.api.call<unsigned long>("gtk_button_get_type")), "FilePicker must use a native GtkButton trigger");
            view.api.call("g_signal_emit_by_name", picker, "clicked"); settle(400);
            W nativePicker = view.controls[pickerCase.first]->dialog;
            check(nativePicker && view.api.call<int>("g_type_check_instance_is_a", nativePicker, view.api.call<unsigned long>("gtk_file_chooser_native_get_type")), "FilePicker must open GtkFileChooserNative");
            check(view.api.call<int>("gtk_file_chooser_get_action", nativePicker) == pickerCase.second, "FilePicker used the wrong native mode");
            view.api.call("g_signal_emit_by_name", nativePicker, "response", -6); idle();
            check(bridge.state()["selectionText.text"] == "File selection cancelled.", "Native picker cancellation did not reach Hydrogen");
            check(view.controls[pickerCase.first]->dialog == nullptr, "Native picker was not disposed");
        }
        view.api.call("g_signal_emit_by_name", view.controls["openDocument"]->widget, "clicked"); settle(400);
        W acceptedPicker = view.controls["openDocument"]->dialog;
        const QString pickedPath = QFileInfo(view.document.sourcePath).absoluteFilePath();
        W pickedFile = view.api.call<W>("g_file_new_for_path", pickedPath.toLocal8Bit().constData());
        check(view.api.call<int>("gtk_file_chooser_set_file", acceptedPicker, pickedFile, nullptr), "Cannot select a native file for picker interaction test");
        view.api.call("g_object_unref", pickedFile);
        settle(500);
        view.api.call("g_signal_emit_by_name", acceptedPicker, "response", -3); idle();
        check(bridge.state()["openDocument.path"].toString() == pickedPath && bridge.state()["selectionText.text"] == "Open: " + pickedPath, "Accepted file path did not reach Hydrogen");
        check(QString::fromUtf8(view.api.call<const char*>("gtk_widget_get_tooltip_text", view.controls["save"]->widget)) == "Write the current plan to the chosen path", "Native button tooltip is missing");
        W details = view.controls["templateDetails"]->widget;
        check(view.api.call<int>("g_type_check_instance_is_a", details, view.api.call<unsigned long>("gtk_scrolled_window_get_type")), "ScrollView must use GtkScrolledWindow");
        check(view.api.call<int>("gtk_widget_get_visible", details), "Hydrogen did not reveal ScrollView");
        settle();
        W scrollAdjustment = view.api.call<W>("gtk_scrolled_window_get_vadjustment", details);
        check(view.api.call<double>("gtk_adjustment_get_upper", scrollAdjustment) > view.api.call<double>("gtk_adjustment_get_page_size", scrollAdjustment), "ScrollView content must overflow its viewport");
        check(QString::fromUtf8(view.api.call<const char*>("gtk_widget_get_tooltip_text", details)) == "Scroll through template details", "Native ScrollView tooltip is missing");
        check(bridge.apply("HYUI\tSET\ttemplateDetails\tenabled\tfalse\n"), "Cannot disable ScrollView");
        check(!view.api.call<int>("gtk_widget_is_sensitive", view.controls["scrollAction"]->widget), "Disabled ScrollView must disable descendants");
        check(bridge.apply("HYUI\tSET\ttemplateDetails\tenabled\ttrue\n"), "Cannot enable ScrollView");
        click("scrollAction");
        check(bridge.state()["selectionText.text"] == "Template chosen from scroll view.", "ScrollView child action did not reach Hydrogen");
        view.api.call("gtk_single_selection_set_selected", view.controls["projects"]->buffer, 1u); idle();
        check(bridge.state()["selectionText.text"] == "Project index: 1", "Table selection did not reach Hydrogen");
        click("showDialog"); until([&] { return view.controls["confirmation"]->dialog != nullptr; }, "Dialog did not open");
        capture("dialog-confirm.png", view.controls["confirmation"]->dialog);
        view.api.call("gtk_dialog_response", view.controls["confirmation"]->dialog, 0); idle();
        check(bridge.state()["dialogResult.text"].toString().startsWith("Confirmed."), "Native dialog response failed");
        const Node* menu = view.controls["showWorkspace"]->node;
        for (auto c : view.controls) { if (c->node->tag == "Menu" && c->node->attributes.value("text") == "Studio") { view.api.call("gtk_menu_button_popup", c->widget); settle(); click(menu->id); view.api.call("gtk_menu_button_popdown", c->widget); break; } }
        check(bridge.state()["pages.value"].toInt() == 0, "Native menu did not select workspace");
        check(view.api.call<unsigned>("g_list_model_get_n_items", view.shortcutController) == 2, "Native menu shortcuts were not registered");
        for (unsigned index : {1u, 0u}) {
            W shortcut = view.api.call<W>("g_list_model_get_item", view.shortcutController, index);
            check(shortcut != nullptr, "Native shortcut is missing");
            check(view.api.call<int>("gtk_shortcut_action_activate", view.api.call<W>("gtk_shortcut_get_action", shortcut), 0, view.window, nullptr), "Native keyboard action did not activate");
            view.api.call("g_object_unref", shortcut); idle();
            check(bridge.state()["pages.value"].toInt() == int(index), "Keyboard shortcut did not reach the Hydrogen menu handler");
        }
        view.api.text(view.controls["projectName"]->widget, "gtk_editable_set_text", "CI Notes"); idle();
        check(bridge.state()["summary.text"].toString().startsWith("CI Notes"), "Input event failed");
        view.api.call("gtk_check_button_set_active", view.controls["symbols"]->widget, 0); idle();
        check(bridge.state()["summary.text"].toString().contains("Debug symbols: false"), "Checkbox event failed");
        view.api.call("gtk_drop_down_set_selected", view.controls["target"]->widget, 2u); idle();
        check(bridge.state()["summary.text"].toString().contains("macOS"), "Select event failed");
        view.api.call("gtk_range_set_value", view.controls["quality"]->widget, 55.0); idle();
        check(bridge.state()["summary.text"].toString().contains("55%"), "Slider event failed");
        view.api.call("gtk_switch_set_active", view.controls["notifications"]->widget, 0);
        check(!bridge.state()["notifications.checked"].toBool(), "Switch event failed");
        view.api.call("gtk_spin_button_set_value", view.controls["workers"]->widget, 8.0); check(bridge.state()["workers.value"].toInt() == 8, "Number input event failed");
        view.api.call("gtk_text_buffer_set_text", view.controls["notes"]->buffer, "Saved by the native UI CI test.", -1);
        click("build"); check(!bridge.state()["build.enabled"].toBool() && bridge.state()["buildTimer.running"].toBool(), "Build did not start progress");
        click("cancel"); check(bridge.state()["build.enabled"].toBool() && !bridge.state()["buildTimer.running"].toBool(), "Cancel did not stop progress");
        click("build"); until([&] { return bridge.state()["progress.value"].toInt() == 100; }, "Timer did not complete progress"); idle();
        check(view.api.call<double>("gtk_progress_bar_get_fraction", view.controls["progress"]->widget) == 1.0 && !view.api.call<int>("gtk_spinner_get_spinning", view.controls["activity"]->widget), "Native progress widgets did not complete");
        check(view.api.call<int>("gtk_widget_get_sensitive", view.controls["save"]->widget), "Save did not become enabled");
        view.api.text(view.controls["savePath"]->widget, "gtk_editable_set_text", output + "/saved-plan.txt"); click("save");
        QFile saved(output + "/saved-plan.txt"); check(saved.open(QIODevice::ReadOnly) && saved.readAll().contains("Saved by the native UI CI test."), "Save did not persist text input");
        layout();
        QFile report(output + "/report.json"); check(report.open(QIODevice::WriteOnly), "Cannot write GTK test report");
        report.write(QJsonDocument(QJsonObject{{"passed", true}, {"platform", "linux"}, {"screenshots", screenshots}, {"captures", captures}, {"state", QJsonObject::fromVariantMap(bridge.state())}}).toJson());
        std::cout << "GTK native interactions and layout passed\n";
    }
};
} }
int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    // Xvfb has no desktop file-chooser portal; exercise the native GTK chooser.
    qputenv("GDK_DEBUG", "no-portals");
    try {
        if (argc != 4) { throw std::runtime_error("expected Studio.hyui, compiler and artifact directory"); }
        QTemporaryDir temporary; QProcess compiler;
        QString sample = QFileInfo(QString::fromUtf8(argv[1])).absoluteFilePath();
        compiler.start(QString::fromUtf8(argv[2]), {"build", QFileInfo(sample).absoluteDir().filePath("Studio.hyproj"), "-o", temporary.filePath("backend"), "--ui-backend", "--hide-progress", "--hide-log", "--hide-spinner"});
        if (!compiler.waitForFinished(120000) || compiler.exitCode() != 0) { throw std::runtime_error(("Cannot build UI sample: " + compiler.readAllStandardError()).toStdString()); }
        QFile file(sample); if (!file.open(QIODevice::ReadOnly)) { throw std::runtime_error("Cannot read sample"); }
        hyui::Document document; if (!document.parse(file.readAll().replace("theme=\"system\"", "theme=\"light\""))) { throw std::runtime_error(document.error.toStdString()); } document.sourcePath = sample;
        hyui::Bridge bridge(document, temporary.filePath("backend"), QFileInfo(sample).absolutePath());
        {
            hyui::GtkView view(document, bridge);
            hyui::GtkUiTests(view, bridge, QFileInfo(QString::fromUtf8(argv[3])).absoluteFilePath()).run();
        }
        if (!bridge.apply("HYUI\tSET\tstatus\ttext\tDisposed safely\n")) { throw std::runtime_error("Bridge failed after GTK view disposal"); }
        return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
