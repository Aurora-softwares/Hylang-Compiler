#include "bridge.hpp"
#include "document.hpp"
#include <QCommandLineParser>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QScreen>
#include <QStandardPaths>
#include <QStyleHints>
#include <QTemporaryDir>
#include <QTextStream>
#include <QTimer>

#ifdef Q_OS_MACOS
void hyuiApplyMacMaterial(QWindow* window, bool glass);
#endif

static bool runTool(const QString& executable, const QStringList& args, const QString& directory,
                    QByteArray& output, QString& error, int timeout = 120000) {
    QProcess child;
    child.setWorkingDirectory(directory);
    child.start(executable, args);
    if (!child.waitForStarted(5000)) { error = child.errorString(); return false; }
    QElapsedTimer clock; clock.start();
    QByteArray errors;
    while (child.state() != QProcess::NotRunning) {
        child.waitForReadyRead(50);
        output += child.readAllStandardOutput(); errors += child.readAllStandardError();
        if (clock.elapsed() > timeout || output.size() > 1024 * 1024 || errors.size() > 1024 * 1024) {
            child.kill(); child.waitForFinished(3000); error = "process timed out or exceeded the output limit"; return false;
        }
    }
    output += child.readAllStandardOutput(); errors += child.readAllStandardError();
    if (child.exitStatus() != QProcess::NormalExit || child.exitCode() != 0) {
        error = QString::fromUtf8(errors + output); return false;
    }
    return true;
}

int main(int argc, char** argv) {
    QGuiApplication app(argc, argv);
    QCoreApplication::setApplicationName("Hydrogen UI");
    QCommandLineParser parser;
    parser.setApplicationDescription("Hydrogen desktop host — HYUI v1 XML with Hydrogen callbacks");
    parser.addHelpOption();
    parser.addOption({"source", "Compile and launch a Hydrogen source/project", "path"});
    parser.addOption({"compiler", "Hydrogen compiler (defaults to sibling hy, then PATH)", "path"});
    parser.addOption({"backend", "Launch an already compiled Hydrogen application", "path"});
    parser.addOption({"document", "Open a HYUI document (standalone preview or backend override)", "path"});
    parser.addOption({"validate", "Validate XML and exit without showing a window"});
    parser.addOption({"style", "Qt Quick Controls style override", "name"});
    parser.addOption({"size", "Requested logical window size, e.g. 1100x820", "WxH"});
    parser.addOption({"screenshot", "Save the rendered application to a PNG and exit", "path"});
    parser.addOption({"event", "Dispatch a registered handler before capture, e.g. Start:start", "handler:sender"});
    parser.addOption({"state-output", "Write resulting control state as JSON (for integration checks)", "path"});
    parser.process(app);
    auto fail = [](const QString& message) { QTextStream(stderr) << "hyui: " << message << '\n'; return 1; };
    if (parser.isSet("source") && parser.isSet("backend")) { return fail("choose either --source or --backend"); }
    QString backend, directory = QDir::currentPath();
    QByteArray startup;
    QTemporaryDir build;
    if (!build.isValid()) { return fail("cannot create a temporary build directory"); }
    if (parser.isSet("source")) {
        QFileInfo source(parser.value("source"));
        if (!source.isFile()) { return fail("source does not exist"); }
        QString compiler = parser.value("compiler");
        if (compiler.isEmpty()) { compiler = qEnvironmentVariable("HYUI_COMPILER"); }
        if (compiler.isEmpty()) {
            compiler = QCoreApplication::applicationDirPath() + "/hy";
#ifdef Q_OS_WIN
            compiler += ".exe";
#endif
            if (!QFileInfo::exists(compiler)) { compiler = QStandardPaths::findExecutable("hy"); }
        }
        compiler = QFileInfo(compiler).absoluteFilePath();
        directory = source.absolutePath();
        backend = build.path() + "/application";
#ifdef Q_OS_WIN
        backend += ".exe";
#endif
        QString error; QByteArray output;
        QString input = source.absoluteFilePath();
        if (source.suffix() == "hy") {
            // Single-file applications get the bundled Hydrogen.UI library.
            // Projects control their own explicit library references.
            if (!QFile::copy(input, build.path() + "/Program.hy") ||
                !QFile::copy(":/hydrogen-ui/Application.hy", build.path() + "/Application.hy")) {
                return fail("cannot prepare the single-file UI project");
            }
            input = build.path() + "/Application.hyproj";
            QFile manifest(input);
            if (!manifest.open(QIODevice::WriteOnly) || manifest.write(
                "format = 2\nname = \"HyuiApplication\"\ntype = \"exe\"\nsources = [\"Program.hy\", \"Application.hy\"]\n") < 0) {
                return fail("cannot write the single-file UI project");
            }
            manifest.close();
        }
        // 'build' is shared by the SDK and self-hosted CLI; project references
        // are resolved by Hydrogen, not reimplemented by the UI host.
        if (!runTool(compiler, {"build", input, "-o", backend}, directory, output, error)) {
            return fail("Hydrogen build failed: " + error);
        }
#ifndef Q_OS_WIN
        // Direct Hydrogen image emission writes bytes, rather than invoking a
        // system linker; make this private temporary backend executable.
        if (!QFile::setPermissions(backend, QFile::permissions(backend) | QFile::ExeOwner)) {
            return fail("cannot make the compiled backend executable");
        }
#endif
    } else if (parser.isSet("backend")) {
        backend = QFileInfo(parser.value("backend")).absoluteFilePath();
        directory = QFileInfo(backend).absolutePath();
    }
    QString documentPath = parser.value("document");
    if (!backend.isEmpty()) {
        QString error;
        if (!runTool(backend, {}, directory, startup, error, 10000)) { return fail("backend launch failed: " + error); }
        if (documentPath.isEmpty()) {
            for (const auto& line : startup.split('\n')) {
                auto parts = QString::fromUtf8(line).trimmed().split('\t');
                if (parts.size() == 3 && parts[0] == "HYUI" && parts[1] == "OPEN") {
                    if (!documentPath.isEmpty()) { return fail("backend opened multiple documents"); }
                    documentPath = QDir(directory).absoluteFilePath(hyui::Bridge::decode(parts[2]));
                }
            }
        }
    }
    if (documentPath.isEmpty()) { return fail("provide --source, --backend, or --document; Main must call Application.Open"); }
    documentPath = QFileInfo(documentPath).absoluteFilePath();
    QFile file(documentPath);
    if (!file.open(QIODevice::ReadOnly)) { return fail("cannot read " + documentPath); }
    hyui::Document document;
    if (!document.parse(file.read(1024 * 1024 + 1))) { return fail(document.error); }
    if (parser.isSet("validate")) { QTextStream(stdout) << "HYUI v1 valid\n"; return 0; }
    if (backend.isEmpty() && !document.handlers.isEmpty()) { return fail("interactive documents require a Hydrogen --source or --backend"); }
    hyui::Bridge bridge(document, backend, directory);
    if (!bridge.apply(startup)) { return fail(bridge.error()); }
    QString style = parser.value("style");
    if (style.isEmpty()) {
#ifdef Q_OS_WIN
        style = "FluentWinUI3";
#elif defined(Q_OS_MACOS)
        style = "macOS";
#else
        style = qEnvironmentVariable("QT_QUICK_CONTROLS_STYLE", "Fusion");
#endif
    }
    QQuickStyle::setStyle(style);
    const QString theme = document.window.attributes.value("theme", "system");
    if (theme != "system") { app.styleHints()->setColorScheme(theme == "dark" ? Qt::ColorScheme::Dark : Qt::ColorScheme::Light); }
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    engine.loadData(document.qml().toUtf8(), QUrl::fromLocalFile(documentPath + ".qml"));
    if (engine.rootObjects().isEmpty()) { return fail("cannot create the HYUI window (check installed Qt Quick Controls modules)"); }
    auto* window = qobject_cast<QQuickWindow*>(engine.rootObjects().first());
    if (!window || !window->screen()) { return fail("no screen available"); }
    if (parser.isSet("size")) {
        QRegularExpression pattern("^([1-9][0-9]{1,4})x([1-9][0-9]{1,4})$");
        auto match = pattern.match(parser.value("size"));
        if (!match.hasMatch()) { return fail("invalid --size; expected WxH"); }
        window->resize(match.captured(1).toInt(), match.captured(2).toInt());
    }
    auto fit = [window] {
        const QRect area = window->screen()->availableGeometry();
        window->resize(qMin(window->width(), qMax(1, area.width() - 24)), qMin(window->height(), qMax(1, area.height() - 64)));
        window->setPosition(area.center() - QPoint(window->width() / 2, window->height() / 2));
    };
    fit();
    QMetaObject::Connection geometryConnection;
    auto watchScreen = [&](QScreen* screen) {
        QObject::disconnect(geometryConnection);
        if (screen) {
            geometryConnection = QObject::connect(screen, &QScreen::availableGeometryChanged, window, [fit](const QRect&) { fit(); });
            fit();
        }
    };
    watchScreen(window->screen());
    QObject::connect(window, &QWindow::screenChanged, window, watchScreen);
    window->show();
#ifdef Q_OS_MACOS
    hyuiApplyMacMaterial(window, document.window.attributes.value("material", "auto") != "solid");
#endif
    const QString onLoad = document.window.attributes.value("onLoad");
    if (!onLoad.isEmpty()) { bridge.dispatch(onLoad, document.window.id); }
    if (parser.isSet("event")) {
        const QStringList event = parser.value("event").split(':');
        if (event.size() != 2) { return fail("--event requires handler:sender"); }
        bridge.dispatch(event[0], event[1]);
    }
    if (parser.isSet("screenshot") || parser.isSet("state-output")) {
        auto capture = [&] {
            if (bridge.busy()) { return; }
            QTimer::singleShot(400, &app, [&] {
                if (bridge.busy()) { return; }
                if (!bridge.error().isEmpty()) { app.exit(fail(bridge.error())); return; }
                if (parser.isSet("screenshot") && !window->grabWindow().save(parser.value("screenshot"))) {
                    app.exit(fail("cannot save screenshot")); return;
                }
                if (parser.isSet("state-output")) {
                    QFile output(parser.value("state-output"));
                    if (!output.open(QIODevice::WriteOnly) || output.write(QJsonDocument::fromVariant(bridge.state()).toJson()) < 0) {
                        app.exit(fail("cannot save state")); return;
                    }
                }
                app.quit();
            });
        };
        QObject::connect(&bridge, &hyui::Bridge::idle, &app, capture);
        QTimer::singleShot(400, &app, capture);
        QTimer::singleShot(15000, &app, [&] { app.exit(fail("capture timed out")); });
    }
    return app.exec();
}
