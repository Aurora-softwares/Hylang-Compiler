#pragma once

#include <memory>
#include <string>

#include "AST.h"
#include "Error.h"

namespace llvm {
class LLVMContext;
class Module;
class raw_ostream;
} // namespace llvm

namespace hy {

class CodeGenerator {
public:
    explicit CodeGenerator(DiagnosticEngine &diag);
    ~CodeGenerator();

    std::unique_ptr<llvm::Module> codegen(const ast::Module &module, const std::string &name);
    void printIR(llvm::Module &module, llvm::raw_ostream &out);
    bool emitObject(llvm::Module &module, const std::string &path);
    bool linkExecutable(const std::string &objectPath, const std::string &outputPath);

private:
    int extractReturnValue(const ast::FuncDecl &fn) const;

    DiagnosticEngine &diag_;
    std::unique_ptr<llvm::LLVMContext> context_;
};

} // namespace hy
