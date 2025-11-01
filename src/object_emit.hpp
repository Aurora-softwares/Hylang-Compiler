#pragma once

#include <string>

namespace llvm {
class Module;
}

namespace hyc {

bool emitObjectFile(llvm::Module &module, const std::string &path, std::string &error);

}
