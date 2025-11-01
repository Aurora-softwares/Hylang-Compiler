#pragma once

#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/Module.h>

namespace winrt {
llvm::Function *getOrCreatePrintFunction(llvm::Module &module);
llvm::Function *getStdHandleDecl(llvm::Module &module);
llvm::Function *getWriteFileDecl(llvm::Module &module);
}
