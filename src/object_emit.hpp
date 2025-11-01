#pragma once

#include <string>

#include <llvm/IR/Module.h>

bool emitObjectFile(llvm::Module &module, const std::string &path, std::string &errorMessage);
