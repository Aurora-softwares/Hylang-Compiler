#pragma once

#include <llvm/IR/Module.h>

namespace llvm {
class Function;
} // namespace llvm

namespace hyc {

class WinRuntime {
  public:
    explicit WinRuntime(llvm::Module &module);

    llvm::Function *getPrintI32();

  private:
    llvm::Function *declareGetStdHandle();
    llvm::Function *declareWriteFile();
    llvm::Function *createPrintI32();

    llvm::Module &m_module;
    llvm::Function *m_printI32 = nullptr;
    llvm::Function *m_getStdHandle = nullptr;
    llvm::Function *m_writeFile = nullptr;
};

} // namespace hyc
