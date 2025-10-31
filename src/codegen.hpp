#pragma once

#include "ast.hpp"

#include <memory>
#include <string>

namespace llvm {
class LLVMContext;
class Module;
}

namespace hydrogenc {

class CodeGenerator {
public:
    CodeGenerator();
    ~CodeGenerator();

    llvm::LLVMContext& context();
    std::unique_ptr<llvm::Module> generate(const Program& program, const std::string& module_name);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace hydrogenc
