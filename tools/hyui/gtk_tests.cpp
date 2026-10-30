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
    void click(const QString& id) { view.api.call("g_signal_emit_by_name", view.controls[id]->widget, "clicked"); idle(); }
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
            view.api.call("gtk_notebook_set_current_page", view.controls["pages"]->widget, page); idle();
            for (int width : {1120, 800, 360}) {
                view.present(width, 900); settle(350); layout();
                if (page == 0) {
                    auto project = bounds(widget("projectName")), summary = bounds(widget("summary"));
                    if (width == 1120) { check(summary.x > project.x + project.width, "Wide panels must be side by side"); }
                    if (width == 360) {
                        check(summary.y > project.y + project.height, "Narrow panels must stack");
                        check(bounds(widget("workers")).y > bounds(widget("target")).y + bounds(widget("target")).height, "Nested row must stack");
                    }
                }
                capture(QString("%1-%2.png").arg(page ? "gallery" : "workspace").arg(width));
            }
        }
        view.present(1120, 900); settle();
        check(view.api.call<W>("gtk_picture_get_paintable", view.controls["logo"]->widget) != nullptr, "Bundled image failed to decode");
        view.api.call("gtk_check_button_set_active", view.controls["channel"]->choices[1], 1); idle();
        check(bridge.state()["channelText.text"] == "Preview channel selected.", "Radio event did not reach Hydrogen");
        view.api.call("gtk_list_box_select_row", view.controls["templates"]->widget, view.api.call<W>("gtk_list_box_get_row_at_index", view.controls["templates"]->widget, 2)); idle();
        check(bridge.state()["selectionText.text"] == "Template index: 2", "List selection did not reach Hydrogen");
        view.api.call("gtk_single_selection_set_selected", view.controls["projects"]->buffer, 1u); idle();
        check(bridge.state()["selectionText.text"] == "Project index: 1", "Table selection did not reach Hydrogen");
        click("showDialog"); until([&] { return view.controls["confirmation"]->dialog != nullptr; }, "Dialog did not open");
        capture("dialog-confirm.png", view.controls["confirmation"]->dialog);
        view.api.call("gtk_dialog_response", view.controls["confirmation"]->dialog, 0); idle();
        check(bridge.state()["dialogResult.text"].toString().startsWith("Confirmed."), "Native dialog response failed");
        const Node* menu = view.controls["showWorkspace"]->node;
        for (auto c : view.controls) { if (c->node->tag == "Menu" && c->node->attributes.value("text") == "Studio") { view.api.call("gtk_menu_button_popup", c->widget); settle(); click(menu->id); view.api.call("gtk_menu_button_popdown", c->widget); break; } }
        check(bridge.state()["pages.value"].toInt() == 0, "Native menu did not select workspace");
        view.api.text(view.controls["projectName"]->widget, "gtk_editable_set_text", "CI Notes"); idle();
        check(bridge.state()["summary.text"].toString().startsWith("CI Notes"), "Input event failed");
        view.api.call("gtk_check_button_set_active", view.controls["symbols"]->widget, 0); idle();
        check(bridge.state()["summary.text"].toString().contains("Debug symbols: false"), "Checkbox event failed");
        view.api.call("gtk_range_set_value", view.controls["quality"]->widget, 55.0); idle();
        check(bridge.state()["summary.text"].toString().contains("55%"), "Slider event failed");
        view.api.call("gtk_switch_set_active", view.controls["notifications"]->widget, 0);
        check(!bridge.state()["notifications.checked"].toBool(), "Switch event failed");
        view.api.call("gtk_spin_button_set_value", view.controls["workers"]->widget, 8.0); check(bridge.state()["workers.value"].toInt() == 8, "Number input event failed");
        view.api.call("gtk_text_buffer_set_text", view.controls["notes"]->buffer, "Saved by the native UI CI test.", -1);
        click("build"); check(!bridge.state()["build.enabled"].toBool() && bridge.state()["buildTimer.running"].toBool(), "Build did not start progress");
        click("cancel"); check(bridge.state()["build.enabled"].toBool() && !bridge.state()["buildTimer.running"].toBool(), "Cancel did not stop progress");
        click("build"); until([&] { return bridge.state()["progress.value"].toInt() == 100; }, "Timer did not complete progress"); idle();
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
    try {
        if (argc != 4) { throw std::runtime_error("expected Studio.hyui, compiler and artifact directory"); }
        QTemporaryDir temporary; QProcess compiler;
        QString sample = QFileInfo(QString::fromUtf8(argv[1])).absoluteFilePath();
        compiler.start(QString::fromUtf8(argv[2]), {"build", QFileInfo(sample).absoluteDir().filePath("Studio.hyproj"), "-o", temporary.filePath("backend"), "--ui-backend", "--hide-progress", "--hide-log", "--hide-spinner"});
        if (!compiler.waitForFinished(120000) || compiler.exitCode() != 0) { throw std::runtime_error(("Cannot build UI sample: " + compiler.readAllStandardError()).toStdString()); }
        QFile file(sample); if (!file.open(QIODevice::ReadOnly)) { throw std::runtime_error("Cannot read sample"); }
        hyui::Document document; if (!document.parse(file.readAll().replace("theme=\"system\"", "theme=\"light\""))) { throw std::runtime_error(document.error.toStdString()); } document.sourcePath = sample;
        hyui::Bridge bridge(document, temporary.filePath("backend"), QFileInfo(sample).absolutePath());
        hyui::GtkView view(document, bridge); hyui::GtkUiTests(view, bridge, QFileInfo(QString::fromUtf8(argv[3])).absoluteFilePath()).run(); return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
