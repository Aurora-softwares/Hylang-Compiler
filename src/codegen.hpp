#pragma once

#include "ast.hpp"
#include "diag.hpp"
#include "winrt.hpp"

#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace hyc {

class CodeGenerator {
  public:
    CodeGenerator(llvm::LLVMContext& ctx, Diagnostics& diags,
                  llvm::Module& module, RuntimeSupport& runtime);

    bool emit_program(Program& program);

  private:
    struct LocalInfo {
        llvm::Value* storage = nullptr;
    };

    void push_scope();
    void pop_scope();
    bool declare_local(const std::string& name, llvm::Value* storage,
                       const SourceLocation& loc);
    llvm::Value* lookup_variable(const std::string& name);

    llvm::AllocaInst* create_alloca(llvm::Function* fn, const std::string& name);

    bool emit_decl(Decl& decl);
    bool emit_function(FunctionDecl& func);
    bool emit_global(GlobalVarDecl& var);

    bool emit_statement(Stmt& stmt, llvm::Function* fn,
                        llvm::IRBuilder<>& builder);
    bool emit_var_decl(VarDeclStmt& stmt, llvm::Function* fn,
                       llvm::IRBuilder<>& builder);
    bool emit_return(ReturnStmt& stmt, llvm::Function* fn,
                     llvm::IRBuilder<>& builder);
    bool emit_expr_stmt(ExprStmt& stmt, llvm::IRBuilder<>& builder);

    llvm::Value* emit_expr(Expr& expr, llvm::IRBuilder<>& builder);
    llvm::Value* emit_assignment(AssignmentExpr& expr,
                                 llvm::IRBuilder<>& builder);
    llvm::Value* emit_call(CallExpr& expr, llvm::IRBuilder<>& builder);

    llvm::Value* load_variable(const std::string& name, llvm::IRBuilder<>& builder,
                               const SourceLocation& loc);

    llvm::Value* emit_integer(IntegerLiteralExpr& expr);

    llvm::GlobalVariable* lookup_global(const std::string& name);

    llvm::LLVMContext& ctx_;
    Diagnostics& diags_;
    llvm::Module& module_;
    RuntimeSupport& runtime_;
    std::vector<std::unordered_map<std::string, LocalInfo>> scopes_;
    std::unordered_map<std::string, llvm::GlobalVariable*> globals_;
    llvm::Function* current_function_ = nullptr;
    bool success_ = true;
};

} // namespace hyc
