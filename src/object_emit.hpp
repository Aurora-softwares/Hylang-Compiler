#pragma once

#include <filesystem>
#include <string>

namespace llvm {
class Module;
}

namespace hydrogenc {

bool emit_object(llvm::Module& module, const std::filesystem::path& path, std::string& error);

}
