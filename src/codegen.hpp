#pragma once

#include "ast.hpp"
#include "sema.hpp"
#include "winrt.hpp"

#include <llvm/IR/IRBuilder.h>

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace llvm {
class Module;
class Function;
class Value;
class AllocaInst;
class BasicBlock;
} // namespace llvm

namespace hyc {

class CodeGenerator {
  public:
    explicit CodeGenerator(Sema &sema);

    std::unique_ptr<llvm::Module> generate(const Program &program, const std::string &moduleName);
    llvm::LLVMContext &context() { return m_context; }

  private:
    struct FunctionContext {
        llvm::Function *function = nullptr;
        llvm::BasicBlock *entry = nullptr;
        bool returned = false;
    };

    llvm::AllocaInst *createAlloca(FunctionContext &ctx, const std::string &name);
    void pushLocalScope();
    void popLocalScope();
    void setLocal(const std::string &name, llvm::AllocaInst *alloca);
    llvm::AllocaInst *getLocal(const std::string &name);

    void declareGlobals(const Program &program);
    void declareFunctions(const Program &program);

    void emitDeclaration(Decl *decl);
    void emitFunction(FunctionDecl *decl);
    void emitBlock(BlockStmt *block, FunctionContext &ctx, bool createScope = true);
    void emitStatement(Stmt *stmt, FunctionContext &ctx);
    void emitVarDecl(VarDeclStmt *stmt, FunctionContext &ctx);
    void emitReturn(ReturnStmt *stmt, FunctionContext &ctx);

    llvm::Value *emitExpr(Expr *expr, FunctionContext &ctx);
    llvm::Value *emitAssignment(AssignmentExpr *expr, FunctionContext &ctx);
    llvm::Value *emitCall(CallExpr *expr, FunctionContext &ctx);

    llvm::Value *getVariable(const std::string &name, FunctionContext &ctx);

    llvm::LLVMContext m_context;
    std::unique_ptr<llvm::Module> m_module;
    std::unique_ptr<llvm::IRBuilder<>> m_builder;
    std::unique_ptr<WinRuntime> m_runtime;
    Sema &m_sema;
    std::unordered_map<std::string, llvm::Function *> m_functionMap;
    std::unordered_map<std::string, llvm::Value *> m_globalValues;
    std::vector<VarDeclStmt *> m_globalInitOrder;
    llvm::Function *m_globalInitFunction = nullptr;
    std::vector<std::unordered_map<std::string, llvm::AllocaInst *>> m_localScopes;
};

} // namespace hyc
