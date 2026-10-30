#include "native_runtime.hpp"
#include "gtk.hpp"
#include <QCoreApplication>
int main(int argc, char** argv) {
#ifdef Q_OS_MACOS
    return hyui::appkitMain(argc, argv);
#else
    return hyui::gtkMain(argc, argv);
#endif
}
