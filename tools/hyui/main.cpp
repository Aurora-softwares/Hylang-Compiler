#include "package.hpp"
#include "native_runtime.hpp"
#include "gtk.hpp"
#include <QCoreApplication>
#include <QByteArray>
int main(int argc, char** argv) {
    for (int i = 1; i < argc; ++i) {
        if (QByteArray(argv[i]) == "--package" || QByteArray(argv[i]) == "--export-runtime") {
            return hyui::packageMain(argc, argv);
        }
    }
#ifdef Q_OS_LINUX
    return hyui::gtkMain(argc, argv);
#elif defined(Q_OS_MACOS)
    return hyui::appkitMain(argc, argv);
#else
    return hyui::windowsMain(argc, argv);
#endif
}
