#pragma once

namespace llvm {
class Module;
}

namespace hydrogenc::winrt {

void inject_runtime(llvm::Module& module);

} // namespace hydrogenc::winrt
