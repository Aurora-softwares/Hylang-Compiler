#include "native_runtime.hpp"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QProcess>
#include <QTemporaryDir>
#include <stdexcept>
namespace hyui {
namespace {
class WinUIView : public NativeView {
    QProcess host;
    QTemporaryDir initial;
public:
    WinUIView(const Document& doc, Bridge& bridge) {
        QString executable = qEnvironmentVariable("HYUI_WINUI_HOST", QCoreApplication::applicationDirPath() + "/native-winui/Hyui.WinUI.exe");
        if (!QFileInfo::exists(executable)) { throw std::runtime_error("the actual WinUI 3 host is missing; build the hyui-winui target on Windows or set HYUI_WINUI_HOST; Qt style replicas are not used"); }
        QFile state(initial.path() + "/state.json");
        if (!state.open(QIODevice::WriteOnly) || state.write(QJsonDocument::fromVariant(bridge.state()).toJson()) < 0) { throw std::runtime_error("cannot prepare native WinUI state"); } state.close();
        host.start(executable, {"--backend", bridge.executablePath(), "--document", doc.sourcePath, "--initial-state", state.fileName()});
        if (!host.waitForStarted(10000)) { throw std::runtime_error("cannot start the Microsoft WinUI host"); }
    }
    void present(int, int) override {}
    void pump() override { if (host.state() == QProcess::NotRunning) { QCoreApplication::exit(host.exitCode()); } }
    bool screenshot(const QString&) override { return false; }
    bool ownsDispatch() const override { return true; }
};
}
int windowsMain(int argc, char** argv) { return nativeMain(argc, argv, [](const Document& doc, Bridge& bridge) { return std::make_unique<WinUIView>(doc, bridge); }); }
}
