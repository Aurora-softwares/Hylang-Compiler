#include "codegen.hpp"

#include <llvm/IR/Constants.h>
#include <llvm/IR/Function.h>
#include <llvm/IR/Verifier.h>

namespace hyc {

CodeGenerator::CodeGenerator(llvm::LLVMContext& ctx, Diagnostics& diags,
                             llvm::Module& module, RuntimeSupport& runtime)
    : ctx_(ctx), diags_(diags), module_(module), runtime_(runtime) {}

void CodeGenerator::push_scope() { scopes_.emplace_back(); }

void CodeGenerator::pop_scope() {
    if (!scopes_.empty()) {
        scopes_.pop_back();
    }
}

bool CodeGenerator::declare_local(const std::string& name, llvm::Value* storage,
                                  const SourceLocation& loc) {
    if (scopes_.empty()) {
        push_scope();
    }
    auto& scope = scopes_.back();
    auto [it, inserted] = scope.emplace(name, LocalInfo{storage});
    if (!inserted) {
        diags_.error(loc, "redefinition of variable '" + name + "'");
        success_ = false;
        return false;
    }
    return true;
}

llvm::Value* CodeGenerator::lookup_variable(const std::string& name) {
    for (auto it = scopes_.rbegin(); it != scopes_.rend(); ++it) {
        auto found = it->find(name);
        if (found != it->end()) {
            return found->second.storage;
        }
    }
    auto g = globals_.find(name);
    if (g != globals_.end()) {
        return g->second;
    }
    return nullptr;
}

llvm::AllocaInst* CodeGenerator::create_alloca(llvm::Function* fn,
                                               const std::string& name) {
    llvm::IRBuilder<> tmp(&fn->getEntryBlock(), fn->getEntryBlock().begin());
    return tmp.CreateAlloca(llvm::Type::getInt32Ty(ctx_), nullptr, name);
}

bool CodeGenerator::emit_program(Program& program) {
    runtime_.get_print_wrapper();

    for (auto& decl : program.decls) {
        if (decl->kind == Decl::Kind::GlobalVar) {
            if (!emit_global(static_cast<GlobalVarDecl&>(*decl))) {
                success_ = false;
            }
        }
    }

    for (auto& decl : program.decls) {
        if (decl->kind == Decl::Kind::Function) {
            if (!emit_function(static_cast<FunctionDecl&>(*decl))) {
                success_ = false;
            }
        }
    }

    runtime_.ensure_runtime();

    return success_ && !diags_.has_errors() &&
           !llvm::verifyModule(module_, &llvm::errs());
}

bool CodeGenerator::emit_decl(Decl& decl) {
    switch (decl.kind) {
    case Decl::Kind::GlobalVar:
        return emit_global(static_cast<GlobalVarDecl&>(decl));
    case Decl::Kind::Function:
        return emit_function(static_cast<FunctionDecl&>(decl));
    }
    return false;
}

bool CodeGenerator::emit_global(GlobalVarDecl& var) {
    llvm::Constant* initializer = nullptr;
    if (var.initializer && var.initializer->kind == Expr::Kind::Integer) {
        auto& int_expr = static_cast<IntegerLiteralExpr&>(*var.initializer);
        initializer = llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx_),
                                             int_expr.value);
    } else {
        diags_.error(var.loc,
                     "global initializers must be integer literals for now");
        success_ = false;
        initializer = llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx_), 0);
    }

    auto* global = new llvm::GlobalVariable(
        module_, llvm::Type::getInt32Ty(ctx_), false, llvm::GlobalValue::ExternalLinkage,
        initializer, var.name);
    globals_.emplace(var.name, global);
    return true;
}

bool CodeGenerator::emit_function(FunctionDecl& func) {
    std::vector<llvm::Type*> param_types(func.params.size(),
                                         llvm::Type::getInt32Ty(ctx_));
    auto* fn_type =
        llvm::FunctionType::get(llvm::Type::getInt32Ty(ctx_), param_types, false);

    llvm::Function* fn = module_.getFunction(func.name);
    if (!fn) {
        fn = llvm::Function::Create(fn_type, llvm::GlobalValue::ExternalLinkage,
                                    func.name, module_);
    } else {
        if (!fn->getFunctionType()->isEqual(fn_type)) {
            diags_.error(func.loc, "function signature mismatch for '" + func.name +
                                       "'");
            return false;
        }
        if (!fn->empty()) {
            diags_.error(func.loc,
                         "duplicate definition of function '" + func.name + "'");
            return false;
        }
    }
    current_function_ = fn;

    llvm::BasicBlock* entry = llvm::BasicBlock::Create(ctx_, "entry", fn);
    llvm::IRBuilder<> builder(entry);

    push_scope();

    std::size_t idx = 0;
    for (auto& arg : fn->args()) {
        arg.setName(func.params[idx].name);
        llvm::AllocaInst* alloca = create_alloca(fn, arg.getName().str());
        builder.CreateStore(&arg, alloca);
        declare_local(func.params[idx].name, alloca, func.params[idx].loc);
        ++idx;
    }

    bool ok = true;
    for (auto& stmt : func.body) {
        if (!emit_statement(*stmt, fn, builder)) {
            ok = false;
        }
        if (builder.GetInsertBlock()->getTerminator()) {
            break;
        }
    }

    if (!builder.GetInsertBlock()->getTerminator()) {
        builder.CreateRet(llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx_), 0));
    }

    pop_scope();
    current_function_ = nullptr;
    return ok;
}

bool CodeGenerator::emit_statement(Stmt& stmt, llvm::Function* fn,
                                   llvm::IRBuilder<>& builder) {
    switch (stmt.kind) {
    case Stmt::Kind::Var:
        return emit_var_decl(static_cast<VarDeclStmt&>(stmt), fn, builder);
    case Stmt::Kind::Return:
        return emit_return(static_cast<ReturnStmt&>(stmt), fn, builder);
    case Stmt::Kind::Expr:
        return emit_expr_stmt(static_cast<ExprStmt&>(stmt), builder);
    }
    return false;
}

bool CodeGenerator::emit_var_decl(VarDeclStmt& stmt, llvm::Function* fn,
                                  llvm::IRBuilder<>& builder) {
    llvm::AllocaInst* alloca = create_alloca(fn, stmt.name);
    if (!declare_local(stmt.name, alloca, stmt.loc)) {
        return false;
    }
    if (!stmt.initializer) {
        diags_.error(stmt.loc, "missing initializer");
        success_ = false;
        return false;
    }
    llvm::Value* init = emit_expr(*stmt.initializer, builder);
    if (!init) {
        return false;
    }
    builder.CreateStore(init, alloca);
    return true;
}

bool CodeGenerator::emit_return(ReturnStmt& stmt, llvm::Function* /*fn*/,
                                llvm::IRBuilder<>& builder) {
    llvm::Value* value = nullptr;
    if (stmt.expression) {
        value = emit_expr(*stmt.expression, builder);
        if (!value) {
            return false;
        }
    } else {
        value = llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx_), 0);
    }
    builder.CreateRet(value);
    return true;
}

bool CodeGenerator::emit_expr_stmt(ExprStmt& stmt, llvm::IRBuilder<>& builder) {
    if (!stmt.expression) {
        diags_.error(stmt.loc, "missing expression");
        success_ = false;
        return false;
    }
    return emit_expr(*stmt.expression, builder) != nullptr;
}

llvm::Value* CodeGenerator::emit_expr(Expr& expr, llvm::IRBuilder<>& builder) {
    switch (expr.kind) {
    case Expr::Kind::Identifier: {
        auto& ident = static_cast<IdentifierExpr&>(expr);
        llvm::Value* storage = lookup_variable(ident.name);
        if (!storage) {
            diags_.error(expr.loc, "unknown identifier '" + ident.name + "'");
            success_ = false;
            return nullptr;
        }
        return builder.CreateLoad(llvm::Type::getInt32Ty(ctx_), storage,
                                  ident.name);
    }
    case Expr::Kind::Integer:
        return emit_integer(static_cast<IntegerLiteralExpr&>(expr));
    case Expr::Kind::Call:
        return emit_call(static_cast<CallExpr&>(expr), builder);
    case Expr::Kind::Assignment:
        return emit_assignment(static_cast<AssignmentExpr&>(expr), builder);
    }
    return nullptr;
}

llvm::Value* CodeGenerator::emit_assignment(AssignmentExpr& expr,
                                            llvm::IRBuilder<>& builder) {
    llvm::Value* storage = lookup_variable(expr.target);
    if (!storage) {
        diags_.error(expr.loc,
                     "assignment to undeclared variable '" + expr.target + "'");
        success_ = false;
        return nullptr;
    }
    if (!expr.value) {
        diags_.error(expr.loc, "missing assignment value");
        success_ = false;
        return nullptr;
    }
    llvm::Value* value = emit_expr(*expr.value, builder);
    if (!value) {
        return nullptr;
    }
    builder.CreateStore(value, storage);
    return value;
}

llvm::Value* CodeGenerator::emit_call(CallExpr& expr,
                                      llvm::IRBuilder<>& builder) {
    llvm::Function* callee = module_.getFunction(expr.callee);
    if (!callee) {
        diags_.error(expr.loc, "unknown function '" + expr.callee + "'");
        success_ = false;
        return nullptr;
    }
    std::vector<llvm::Value*> args;
    args.reserve(expr.args.size());
    for (auto& arg : expr.args) {
        if (!arg) {
            diags_.error(expr.loc, "missing call argument");
            success_ = false;
            return nullptr;
        }
        llvm::Value* value = emit_expr(*arg, builder);
        if (!value) {
            return nullptr;
        }
        args.push_back(value);
    }
    llvm::Value* call = builder.CreateCall(callee, args);
    if (callee->getReturnType()->isVoidTy()) {
        return llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx_), 0);
    }
    return call;
}

llvm::Value* CodeGenerator::load_variable(const std::string& name,
                                          llvm::IRBuilder<>& builder,
                                          const SourceLocation& loc) {
    llvm::Value* storage = lookup_variable(name);
    if (!storage) {
        diags_.error(loc, "unknown identifier '" + name + "'");
        success_ = false;
        return nullptr;
    }
    return builder.CreateLoad(llvm::Type::getInt32Ty(ctx_), storage, name);
}

llvm::Value* CodeGenerator::emit_integer(IntegerLiteralExpr& expr) {
    return llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx_), expr.value);
}

llvm::GlobalVariable* CodeGenerator::lookup_global(const std::string& name) {
    auto it = globals_.find(name);
    if (it != globals_.end()) {
        return it->second;
    }
    return nullptr;
}

} // namespace hyc
