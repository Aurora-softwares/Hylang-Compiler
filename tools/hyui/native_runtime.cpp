#include "native_runtime.hpp"
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QTemporaryDir>
#include <QTextStream>
#include <QTimer>
#include <stdexcept>
namespace hyui {
namespace {
QByteArray fileText(const QString& path) {
    QFile file(path); if (!file.open(QIODevice::ReadOnly)) { throw std::runtime_error(("cannot read " + path).toStdString()); } return file.readAll();
}
QByteArray execute(const QString& command, const QStringList& args, const QString& directory, int timeout = 180000) {
    QProcess process; process.setWorkingDirectory(directory); process.start(command, args);
    if (!process.waitForStarted(5000) || !process.waitForFinished(timeout)) { process.kill(); process.waitForFinished(); throw std::runtime_error("cannot start or complete the Hydrogen backend build"); }
    QByteArray result = process.readAllStandardOutput();
    if (process.exitCode() != 0 || process.exitStatus() != QProcess::NormalExit) { throw std::runtime_error((result + process.readAllStandardError()).toStdString()); }
    return result;
}
}

int nativeMain(int argc, char** argv, NativeFactory factory) {
    QCoreApplication app(argc, argv);
    QCommandLineParser parser; parser.addHelpOption();
    for (const QString& option : {"source", "backend", "compiler", "document", "bundle", "size", "event", "screenshot", "state-output"}) { parser.addOption({option, option, "value"}); }
    parser.addOption({"validate", "Validate the view"}); parser.process(app);
#ifdef Q_OS_LINUX
    if (parser.isSet("screenshot") && qEnvironmentVariableIsEmpty("GSK_RENDERER")) { qputenv("GSK_RENDERER", "cairo"); }
#endif
    try {
        QTemporaryDir temporary;
        QString backend, view = parser.value("document"), directory = QDir::currentPath();
        QByteArray startup;
        if (parser.isSet("bundle")) {
            if (parser.isSet("source") || parser.isSet("backend") || parser.isSet("document") || parser.isSet("compiler")) { throw std::runtime_error("packaged apps cannot replace their backend or view"); }
            directory = QFileInfo(parser.value("bundle")).absoluteFilePath();
            auto config = QJsonDocument::fromJson(fileText(directory + "/__hyui_app.json")).object();
            if (config["format"].toInt() != 1) { throw std::runtime_error("unsupported application bundle"); }
            auto resource = [&](const QString& key) {
                QString name = QDir::cleanPath(config[key].toString());
                QString file = QDir(directory).absoluteFilePath(name);
                if (name == "." || name == ".." || name.startsWith("../") || QDir::isAbsolutePath(name) || !QFileInfo(file).canonicalFilePath().startsWith(QFileInfo(directory).canonicalFilePath() + '/')) { throw std::runtime_error("invalid packaged resource path"); }
                return file;
            };
            backend = resource("backend"); view = resource("document");
        } else if (parser.isSet("source")) {
            QString source = QFileInfo(parser.value("source")).absoluteFilePath(); directory = QFileInfo(source).absolutePath();
            QString compiler = parser.value("compiler"); if (compiler.isEmpty()) { compiler = qEnvironmentVariable("HYUI_COMPILER", QCoreApplication::applicationDirPath() + "/hy"); }
            compiler = QFileInfo(compiler).absoluteFilePath();
            if (source.endsWith(".hy")) {
                if (!QFile::copy(source, temporary.path() + "/Program.hy") || !QFile::copy(":/hydrogen-ui/Application.hy", temporary.path() + "/Application.hy")) { throw std::runtime_error("cannot prepare the single-file project"); }
                source = temporary.path() + "/Application.hyproj";
                QFile manifest(source); if (!manifest.open(QIODevice::WriteOnly)) { throw std::runtime_error("cannot write the single-file project"); }
                manifest.write("format = 2\nname = \"UI\"\ntype = \"exe\"\nsources = [\"Program.hy\", \"Application.hy\"]\n"); manifest.close();
            }
            backend = temporary.path() + "/backend";
            execute(compiler, {"build", source, "-o", backend, "--ui-backend"}, directory);
            QFile::setPermissions(backend, QFile::permissions(backend) | QFile::ExeOwner);
        } else if (parser.isSet("backend")) { backend = QFileInfo(parser.value("backend")).absoluteFilePath(); directory = QFileInfo(backend).absolutePath(); }
        if (!backend.isEmpty()) {
            startup = execute(backend, {}, directory, 10000);
            if (view.isEmpty()) {
                for (const auto& line : startup.split('\n')) {
                    auto fields = QString::fromUtf8(line).split('\t');
                    if (fields.size() == 3 && fields[0] == "HYUI" && fields[1] == "OPEN") { view = QDir(directory).absoluteFilePath(Bridge::decode(fields[2].trimmed())); }
                }
            }
        }
        if (view.isEmpty()) { throw std::runtime_error("Main must select a view with Application.Open"); }
        Document document; if (!document.parse(fileText(view))) { throw std::runtime_error(document.error.toStdString()); }
        document.sourcePath = QFileInfo(view).absoluteFilePath();
        if (parser.isSet("validate")) { QTextStream(stdout) << "HYUI v1 valid\n"; return 0; }
        Bridge bridge(document, backend, directory); if (!bridge.apply(startup)) { throw std::runtime_error(bridge.error().toStdString()); }
        auto native = factory(document, bridge);
        int width = document.window.attributes.value("width", "1100").toInt(), height = document.window.attributes.value("height", "820").toInt();
        if (parser.isSet("size")) { auto size = parser.value("size").split('x'); if (size.size() != 2 || size[0].toInt() < 1 || size[1].toInt() < 1) { throw std::runtime_error("invalid window size"); } width = size[0].toInt(); height = size[1].toInt(); }
        native->present(width, height);
        QTimer events; events.setInterval(8); QObject::connect(&events, &QTimer::timeout, &app, [&] { native->pump(); }); events.start();
        if (!native->ownsDispatch() && document.window.attributes.contains("onLoad")) { bridge.dispatch(document.window.attributes["onLoad"], document.window.id); }
        if (parser.isSet("event")) { auto event = parser.value("event").split(':'); if (event.size() != 2) { throw std::runtime_error("event must be handler:sender"); } bridge.dispatch(event[0], event[1]); }
        if (parser.isSet("screenshot") || parser.isSet("state-output")) {
            QTimer* check = new QTimer(&app); check->setInterval(700);
            QObject::connect(check, &QTimer::timeout, &app, [&] {
                if (bridge.busy()) { return; }
                if (!bridge.error().isEmpty()) { QTextStream(stderr) << bridge.error(); app.exit(1); return; }
                if (parser.isSet("screenshot") && !native->screenshot(parser.value("screenshot"))) { return; }
                if (parser.isSet("state-output")) { QFile file(parser.value("state-output")); if (!file.open(QIODevice::WriteOnly) || file.write(QJsonDocument::fromVariant(bridge.state()).toJson()) < 0) { app.exit(1); return; } }
                app.quit();
            }); check->start(); QTimer::singleShot(15000, &app, [&] { QTextStream(stderr) << "native window did not become ready for capture\n"; app.exit(1); });
        }
        return app.exec();
    } catch (const std::exception& error) { QTextStream(stderr) << "hyui native: " << error.what() << '\n'; return 1; }
}
}
