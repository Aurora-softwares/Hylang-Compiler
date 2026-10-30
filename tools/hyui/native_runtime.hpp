#pragma once
#include "bridge.hpp"
#include <functional>
#include <memory>
namespace hyui {
class NativeView {
public:
    virtual ~NativeView() = default;
    virtual void present(int width, int height) = 0;
    virtual void pump() = 0;
    virtual bool screenshot(const QString& path) = 0;
    virtual bool ownsDispatch() const { return false; }
};
using NativeFactory = std::function<std::unique_ptr<NativeView>(const Document&, Bridge&)>;
int nativeMain(int argc, char** argv, NativeFactory factory);
std::unique_ptr<NativeView> createAppKitView(const Document& document, Bridge& bridge);
int appkitMain(int argc, char** argv);
int windowsMain(int argc, char** argv);
}
