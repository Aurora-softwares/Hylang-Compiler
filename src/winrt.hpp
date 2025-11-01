#pragma once

#include <llvm/IR/Function.h>
#include <llvm/IR/Module.h>

namespace hyc {

class RuntimeSupport {
  public:
    explicit RuntimeSupport(llvm::Module& module);

    void ensure_runtime();

    llvm::Function* get_print_wrapper();

  private:
    llvm::Function* ensure_print_function();
    llvm::Function* ensure_print_wrapper();
    llvm::Function* ensure_entry_function();
    llvm::Function* declare_get_std_handle();
    llvm::Function* declare_write_file();
    llvm::Function* declare_exit_process();

    llvm::Module& module_;
    llvm::Function* print_intrinsic_ = nullptr;
    llvm::Function* print_wrapper_ = nullptr;
    llvm::Function* entry_function_ = nullptr;
};

} // namespace hyc
