#pragma once

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>

#include "ast.hpp"
#include "diag.hpp"
#include "sema.hpp"

class CodeGenerator {
public:
    CodeGenerator(DiagnosticsEngine &diag, const Sema &sema, std::string moduleName);

    bool generate(Program &program);

    llvm::Module &module() { return *module_; }
    llvm::LLVMContext &context() { return context_; }

private:
    llvm::Type *toLLVMType(SimpleType type);
    llvm::Value *emitExpr(Expr &expr);
    void emitStatement(Statement &stmt);
    void emitVarDecl(VarDecl &decl);
    llvm::Value *emitAssignment(Expr::Assignment &assign);
    void emitReturn(Statement::ReturnStmt &stmt);

    void emitFunction(FunctionDecl &decl);
    void emitGlobal(VarDecl &decl);
    llvm::AllocaInst *createEntryAlloca(const std::string &name);
    llvm::Value *getVariable(const std::string &name);

    DiagnosticsEngine &diag_;
    const Sema &sema_;
    llvm::LLVMContext context_;
    std::unique_ptr<llvm::Module> module_;
    llvm::IRBuilder<> builder_;

    FunctionDecl *currentFunction_{nullptr};
    llvm::Function *currentLLVMFunction_{nullptr};
    llvm::BasicBlock *returnBlock_{nullptr};
    std::unordered_map<std::string, llvm::AllocaInst *> locals_;
    std::vector<std::unordered_map<std::string, llvm::AllocaInst *>> scopeStack_;
    std::unordered_map<std::string, llvm::GlobalVariable *> globals_;
    std::unordered_map<std::string, llvm::Function *> functions_;
};
