#include "package.hpp"
#include "document.hpp"
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLibraryInfo>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QSysInfo>
#include <QTemporaryDir>
#include <QTextStream>
#include <QUuid>
#include <stdexcept>

namespace hyui {
namespace {
void require(bool condition, const QString& message) {
    if (!condition) { throw std::runtime_error(message.toUtf8().constData()); }
}
QByteArray read(const QString& path) {
    QFile file(path);
    require(file.open(QIODevice::ReadOnly), "cannot read " + path);
    return file.readAll();
}
void write(const QString& path, const QByteArray& contents) {
    require(QDir().mkpath(QFileInfo(path).absolutePath()), "cannot create output directory");
    QFile file(path);
    require(file.open(QIODevice::WriteOnly) && file.write(contents) == contents.size(), "cannot write " + path);
}
void copy(const QString& source, const QString& destination) {
    QFileInfo info(source);
    require(info.exists(), "missing runtime or asset: " + source);
    if (info.isDir()) {
        require(QDir().mkpath(destination), "cannot create " + destination);
        for (const auto& child : QDir(source).entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden)) {
            copy(child.absoluteFilePath(), destination + "/" + child.fileName());
        }
    } else {
        require(QDir().mkpath(QFileInfo(destination).absolutePath()), "cannot create output directory");
        if (QFileInfo::exists(destination)) { require(QFile::remove(destination), "cannot replace staged file"); }
        require(QFile::copy(source, destination), "cannot copy " + source + " to " + destination);
    }
}
QByteArray run(const QString& program, const QStringList& args, int timeout = 180000) {
    require(!program.isEmpty(), "a required deployment tool was not found");
    QProcess process;
    process.start(program, args);
    require(process.waitForStarted(5000), "cannot start " + program + ": " + process.errorString());
    if (!process.waitForFinished(timeout)) { process.kill(); process.waitForFinished(); throw std::runtime_error("build or deployment timed out"); }
    QByteArray output = process.readAllStandardOutput();
    require(process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0,
        program + " failed:\n" + QString::fromUtf8(output + process.readAllStandardError()));
    return output;
}
QString nativeTarget() {
#ifdef Q_OS_WIN
    return "windows-x64";
#elif defined(Q_OS_MACOS)
    return "macos-x64";
#else
    return "linux-x64";
#endif
}
QString targetName(QString target) {
    if (target.isEmpty() || target == "exe") { return nativeTarget(); }
    if (target == "linux" || target == "linux-x64") { return "linux-x64"; }
    if (target == "windows" || target == "windows-x64") { return "windows-x64"; }
    if (target == "mac" || target == "macos" || target == "macos-x64") { return "macos-x64"; }
    require(false, "unsupported UI target: " + target);
    return {};
}
QString compilerPath(const QString& selected) {
    QString compiler = selected.isEmpty() ? qEnvironmentVariable("HYUI_COMPILER") : selected;
    if (compiler.isEmpty()) {
        compiler = QCoreApplication::applicationDirPath() + "/hy";
#ifdef Q_OS_WIN
        compiler += ".exe";
#endif
    }
    if (!QFileInfo::exists(compiler)) { compiler = QStandardPaths::findExecutable(compiler); }
    require(!compiler.isEmpty(), "Hydrogen compiler not found; set HYUI_COMPILER or --compiler");
    return QFileInfo(compiler).absoluteFilePath();
}
QMap<QString, QString> fields(const QByteArray& data) {
    QMap<QString, QString> result;
    const auto lines = QString::fromUtf8(data).split('\n');
    bool root = true;
    for (int i = 0; i < lines.size(); ++i) {
        QString line = lines[i].trimmed();
        if (line.isEmpty() || line.startsWith('#') || line.startsWith("//")) { continue; }
        if (line.startsWith('[')) { root = false; }
        if (!root) { continue; }
        int equal = line.indexOf('=');
        if (equal < 0) { continue; }
        QString key = line.left(equal).trimmed(), value = line.mid(equal + 1).trimmed();
        if (value.startsWith('[')) {
            while (!value.endsWith(']') && i + 1 < lines.size()) { value += "\n" + lines[++i].trimmed(); }
        }
        require(!result.contains(key), "duplicate project field: " + key);
        result[key] = value;
    }
    return result;
}
QString stringField(const QMap<QString, QString>& values, const QString& key) {
    QString value = values.value(key);
    require(value.size() >= 2 && value.startsWith('"') && value.endsWith('"') && !value.mid(1, value.size() - 2).contains('"'), "expected quoted " + key + " in the project manifest");
    return value.mid(1, value.size() - 2);
}
QString safeAsset(const QString& sourceRoot, const QString& relative) {
    QString clean = QDir::cleanPath(relative);
    require(!relative.isEmpty() && !QDir::isAbsolutePath(relative) && clean != "." && clean != ".." && !clean.startsWith("../") && !clean.startsWith("__hyui"), "UI assets must be relative paths inside the project: " + relative);
    QString path = QDir(sourceRoot).absoluteFilePath(clean);
    QFileInfo file(path);
    require(file.exists() && !file.isSymLink() && file.canonicalFilePath().startsWith(QFileInfo(sourceRoot).canonicalFilePath() + '/'), "asset is missing or escapes the project directory: " + relative);
    if (file.isDir()) {
        QDirIterator entries(path, QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden, QDirIterator::Subdirectories);
        while (entries.hasNext()) { entries.next(); require(!entries.fileInfo().isSymLink(), "symlinked UI assets are not supported"); }
    }
    return clean;
}

void deployLinux(const QString& runtime) {
    // The desktop's GTK/libadwaita libraries remain system dependencies so
    // their controls and chrome follow OS updates. Only the nonvisual Qt Core
    // event/process/XML support is redistributed with the native host.
    QStringList binaries = {runtime + "/hyui"};
    QDirIterator files(runtime, QDir::Files, QDirIterator::Subdirectories);
    while (files.hasNext()) { QString file = files.next(); if (file.endsWith(".so")) { binaries.append(file); } }
    QSet<QString> libraries;
    const QRegularExpression dependency("=>\\s+(/[^\\n]+?)\\s+\\(");
    const QRegularExpression privateSupport("^(libQt6Core\\.so|libicu|libdouble-conversion\\.so|libb2\\.so|libpcre2-16\\.so)");
    const QString ldd = QStandardPaths::findExecutable("ldd");
    for (const auto& binary : binaries) {
        QString dependencies = QString::fromUtf8(run(ldd, {binary}, 30000));
        require(!dependencies.contains("not found"), "runtime has unresolved libraries: " + binary + "\n" + dependencies);
        auto matches = dependency.globalMatch(dependencies);
        while (matches.hasNext()) {
            QString file = matches.next().captured(1);
            if (privateSupport.match(QFileInfo(file).fileName()).hasMatch()) { libraries.insert(file); }
        }
    }
    for (const auto& library : libraries) { copy(library, runtime + "/lib/" + QFileInfo(library).fileName()); }
    write(runtime + "/qt.conf", "[Paths]\nPrefix=.\nLibraries=lib\n");
}

void exportRuntime(const QString& destination, const QString& target) {
    require(target == nativeTarget(), "runtime export must run on the target system");
    require(QSysInfo::currentCpuArchitecture() == "x86_64", "the current Hydrogen desktop backend requires an x86-64 native runtime");
    QString suffix = target == "windows-x64" ? ".exe" : "";
    const bool mac = target == "macos-x64";
    QString executableDirectory = destination + (mac ? "/MacOS" : "");
    copy(QCoreApplication::applicationDirPath() + "/hyui-launcher" + suffix, executableDirectory + "/hyui-launcher" + suffix);
    QTemporaryDir imports;
    require(imports.isValid(), "cannot create a deployment workspace");
    if (target != "windows-x64") { copy(QCoreApplication::applicationDirPath() + "/hyui-native", executableDirectory + "/hyui"); }
    if (target == "linux-x64") { deployLinux(destination); }
    else if (target == "windows-x64") {
        QString prebuilt = QCoreApplication::applicationDirPath() + "/native-winui";
        if (QFileInfo::exists(prebuilt + "/Hyui.WinUI.exe")) { copy(prebuilt, destination); }
        else {
            for (const QString& file : {"Hyui.WinUI.csproj", "App.xaml", "App.xaml.cs", "app.manifest"}) { write(imports.path() + '/' + file, read(":/native-winui/" + file)); }
            QString dotnet = QStandardPaths::findExecutable("dotnet");
            require(!dotnet.isEmpty(), "the prebuilt WinUI 3 host is missing; install the .NET 8+ SDK to build it");
            run(dotnet, {"publish", imports.path() + "/Hyui.WinUI.csproj", "-c", "Release", "-r", "win-x64", "-o", destination}, 300000);
        }
        copy(destination + "/Hyui.WinUI.exe", destination + "/hyui.exe");
    } else {
        // macdeployqt expects a real .app hierarchy while rewriting framework
        // install names; exportRuntime's destination is that bundle's Contents.
        write(destination + "/Info.plist", "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleExecutable</key><string>hyui-launcher</string><key>CFBundleIdentifier</key><string>software.aurora.hydrogen.app</string><key>CFBundlePackageType</key><string>APPL</string><key>NSHighResolutionCapable</key><true/></dict></plist>");
        QString deploy = QLibraryInfo::path(QLibraryInfo::BinariesPath) + "/macdeployqt";
        require(QFileInfo::exists(deploy), "install the Qt macdeployqt tool to package macOS apps");
        run(deploy, {QFileInfo(destination).absolutePath(), "-executable=" + executableDirectory + "/hyui", "-no-codesign"});
    }
    // Retain the toolkit's license notices alongside redistributed libraries.
    const QString licenses = QLibraryInfo::path(QLibraryInfo::PrefixPath) + "/LICENSES";
    if (QFileInfo::exists(licenses)) { copy(licenses, destination + "/licenses/Qt"); }
    write(destination + "/hyui-runtime.json", QJsonDocument(QJsonObject{{"format", 1}, {"target", target}, {"renderer", mac ? "appkit" : target == "windows-x64" ? "winui3" : "gtk4"}, {"qt", qVersion()}}).toJson());
}

void validateRuntime(const QString& path, const QString& target) {
    QJsonObject manifest = QJsonDocument::fromJson(read(path + "/hyui-runtime.json")).object();
    require(manifest.value("format").toInt() == 1 && manifest.value("target").toString() == target, "native UI runtime does not match target " + target);
    QString renderer = target == "macos-x64" ? "appkit" : target == "windows-x64" ? "winui3" : "gtk4";
    require(manifest.value("renderer").toString() == renderer, "the target runtime must use real " + renderer + " controls; Qt style replicas are not accepted");
    const QString prefix = target == "macos-x64" ? "/MacOS/" : "/";
    const QString suffix = target == "windows-x64" ? ".exe" : "";
    require(QFileInfo::exists(path + prefix + "hyui" + suffix) && QFileInfo::exists(path + prefix + "hyui-launcher" + suffix), "target runtime is missing its desktop host or launcher");
    QByteArray magic = read(path + prefix + "hyui" + suffix).left(4);
    require((target == "linux-x64" && magic == QByteArray::fromHex("7f454c46")) ||
            (target == "windows-x64" && magic.startsWith("MZ")) ||
            (target == "macos-x64" && (magic == QByteArray::fromHex("cffaedfe") || magic == QByteArray::fromHex("cafebabe"))),
            "desktop host binary does not match the requested target");
}

// Publish only complete packages. Existing outputs are restored on a failed
// replacement, and arbitrary directories are never treated as owned runtimes.
void publish(const QList<QPair<QString, QString>>& paths, const QString& target) {
    QString suffix = ".previous-" + QUuid::createUuid().toString(QUuid::Id128);
    QList<QPair<QString, QString>> backups, installed;
    for (const auto& entry : paths) {
        const QFileInfo old(entry.second);
        require(!old.isSymLink(), "refusing to replace a symlink output");
        if (old.isDir()) {
            QString marker = entry.second + (target == "macos-x64" ? "/Contents" : "") + "/hyui-runtime.json";
            require(QFileInfo::exists(marker), "output directory is not an existing Hydrogen UI package: " + entry.second);
        }
    }
    try {
        for (const auto& entry : paths) {
            if (QFileInfo::exists(entry.second)) {
                QString backup = entry.second + suffix;
                require(QDir().rename(entry.second, backup), "cannot back up existing output");
                backups.append(qMakePair(backup, entry.second));
            }
            require(QDir().rename(entry.first, entry.second), "cannot publish " + entry.second);
            installed.append(entry);
        }
    } catch (...) {
        for (auto it = installed.crbegin(); it != installed.crend(); ++it) {
            if (QFileInfo(it->second).isDir()) { QDir(it->second).removeRecursively(); } else { QFile::remove(it->second); }
        }
        for (const auto& backup : backups) { QDir().rename(backup.first, backup.second); }
        throw;
    }
    for (const auto& backup : backups) {
        if (QFileInfo(backup.first).isDir()) { QDir(backup.first).removeRecursively(); } else { QFile::remove(backup.first); }
    }
}
}

int packageMain(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    QCommandLineParser parser;
    parser.addHelpOption();
    parser.addOption({"package", "Build a double-clickable UI application", "project.hyproj"});
    parser.addOption({"output", "Application output path", "path"});
    parser.addOption({"target", "linux, windows, macos (x86-64)", "name"});
    parser.addOption({"compiler", "Hydrogen compiler executable", "path"});
    parser.addOption({"runtime", "Exported native UI runtime for the target platform", "directory"});
    parser.addOption({"export-runtime", "Export a deployable native UI runtime", "directory"});
    parser.process(app);
    try {
        if (parser.isSet("export-runtime")) {
            QString target = targetName(parser.value("target"));
            QString output = QFileInfo(parser.value("export-runtime")).absoluteFilePath();
            require(!QFileInfo::exists(output), "runtime export destination already exists");
            require(QDir().mkpath(QFileInfo(output).absolutePath()), "cannot create runtime export parent");
            QTemporaryDir stage(QFileInfo(output).absolutePath() + "/.hyui-runtime-XXXXXX");
            require(stage.isValid(), "cannot stage runtime export");
            QString staged = stage.path() + (target == "macos-x64" ? "/Runtime.app" : "/runtime");
            if (target == "macos-x64") {
                require(output.endsWith(".app"), "macOS runtime export output must end in .app");
                exportRuntime(staged + "/Contents", target);
            } else { exportRuntime(staged, target); }
            publish({qMakePair(staged, output)}, target);
            QTextStream(stdout) << "exported " << output << '\n';
            return 0;
        }
        require(parser.isSet("package") && parser.isSet("output"), "--package and --output are required");
        QString project = QFileInfo(parser.value("package")).absoluteFilePath();
        QMap<QString, QString> projectFields = fields(read(project));
        require(projectFields.value("format") == "2", "UI packaging requires a format 2 project");
        QString type = stringField(projectFields, "type");
        require(QStringList{"exe", "windows", "macos"}.contains(type), "UI projects require a desktop executable type");
        QString target = targetName(parser.isSet("target") ? parser.value("target") : type);
        const bool mac = target == "macos-x64", windows = target == "windows-x64";
        QString output = QFileInfo(parser.value("output")).absoluteFilePath();
        if (mac && !output.endsWith(".app")) { output += ".app"; }
        if (windows && !output.endsWith(".exe", Qt::CaseInsensitive)) { output += ".exe"; }
        QString root = QFileInfo(project).absolutePath();
        QString view = safeAsset(root, stringField(projectFields, "ui"));
        require(QFileInfo(root + '/' + view).isFile(), "ui must name a .hyui file");
        Document document;
        require(document.parse(read(root + '/' + view)), document.error);
        QStringList assets = {view};
        if (projectFields.contains("ui_assets")) {
            QJsonParseError error;
            QJsonDocument list = QJsonDocument::fromJson(projectFields["ui_assets"].toUtf8(), &error);
            require(error.error == QJsonParseError::NoError && list.isArray(), "ui_assets must be an array of quoted relative paths");
            for (const auto& value : list.array()) {
                require(value.isString(), "ui_assets must contain strings");
                assets.append(safeAsset(root, value.toString()));
            }
        }
        QString runtimeSource = parser.value("runtime");
        if (runtimeSource.isEmpty()) {
            QString runtimeRoot = qEnvironmentVariable("HYUI_RUNTIME_ROOT");
            if (!runtimeRoot.isEmpty()) {
                runtimeSource = QDir(runtimeRoot).absoluteFilePath(target);
                if (mac && !QFileInfo::exists(runtimeSource) && QFileInfo::exists(runtimeSource + ".app")) { runtimeSource += ".app"; }
            }
        }
        if (runtimeSource.isEmpty() && target != nativeTarget()) {
            require(false, "no " + target + " native UI runtime available; export one with hyui --export-runtime on the target system and set HYUI_RUNTIME_ROOT (or --runtime)");
        }
        if (!runtimeSource.isEmpty()) {
            runtimeSource = QFileInfo(runtimeSource).absoluteFilePath();
            if (mac && runtimeSource.endsWith(".app")) { runtimeSource += "/Contents"; }
            validateRuntime(runtimeSource, target);
        }
        require(QDir().mkpath(QFileInfo(output).absolutePath()), "cannot create output parent directory");
        QTemporaryDir stage(QFileInfo(output).absolutePath() + "/.hyui-package-XXXXXX");
        require(stage.isValid(), "cannot create package staging directory");
        QString package = stage.path() + (mac ? "/Application.app" : "/runtime");
        QString runtime = package + (mac ? "/Contents" : "");
        if (runtimeSource.isEmpty()) { exportRuntime(runtime, target); } else { copy(runtimeSource, runtime); }
        validateRuntime(runtime, target);
        QString appDirectory = runtime + (mac ? "/Resources/app" : "/app");
        require(QDir().mkpath(appDirectory), "cannot create app resource directory");
        QString backend = appDirectory + "/__hyui_backend" + (windows ? ".exe" : "");
        QString buildTarget = target == "linux-x64" ? "exe" : windows ? "windows" : "macos";
        run(compilerPath(parser.value("compiler")), {"build", project, "-o", backend, "--target", buildTarget, "--ui-backend"});
        require(QFileInfo::exists(backend), "compiler did not produce the UI backend");
        require(QFile::setPermissions(backend, QFile::permissions(backend) | QFile::ExeOwner | QFile::ExeGroup | QFile::ExeOther), "cannot make the backend executable");
        for (const auto& asset : assets) { copy(root + '/' + asset, appDirectory + '/' + asset); }
        write(appDirectory + "/__hyui_app.json", QJsonDocument(QJsonObject{{"format", 1}, {"document", view}, {"backend", QFileInfo(backend).fileName()}, {"target", target}}).toJson());
        if (mac) {
            publish({qMakePair(package, output)}, target);
        } else {
            QString launcher = stage.path() + "/launcher";
            copy(runtime + "/hyui-launcher" + (windows ? ".exe" : ""), launcher);
            publish({qMakePair(package, output + ".runtime"), qMakePair(launcher, output)}, target);
        }
        QTextStream(stdout) << "wrote " << output << " (" << target << "; bundled UI and native desktop host)\n";
        return 0;
    } catch (const std::exception& error) {
        QTextStream(stderr) << "hyui package: " << error.what() << '\n';
        return 1;
    }
}
}
