#include "codegen.hpp"

#include <llvm/IR/BasicBlock.h>
#include <llvm/IR/Constants.h>
#include <llvm/IR/DerivedTypes.h>
#include <llvm/IR/Function.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>
#include <llvm/IR/Type.h>
#include <llvm/IR/Verifier.h>
#include <llvm/Support/raw_ostream.h>

#include <stdexcept>
#include <vector>
#include <string>

namespace hyc {

CodeGenerator::CodeGenerator(Sema &sema) : m_context(), m_module(), m_builder(), m_runtime(), m_sema(sema) {}

std::unique_ptr<llvm::Module> CodeGenerator::generate(const Program &program, const std::string &moduleName) {
    m_module = std::make_unique<llvm::Module>(moduleName, m_context);
    m_module->setTargetTriple("x86_64-pc-windows-msvc");
    m_builder = std::make_unique<llvm::IRBuilder<>>(m_context);
    m_runtime = std::make_unique<WinRuntime>(*m_module);

    declareGlobals(program);
    declareFunctions(program);

    for (auto &declPtr : program.declarations) {
        emitDeclaration(declPtr.get());
    }

    if (!m_globalInitOrder.empty()) {
        auto *voidTy = llvm::Type::getVoidTy(m_context);
        auto *fnTy = llvm::FunctionType::get(voidTy, false);
        m_globalInitFunction = llvm::Function::Create(fnTy, llvm::GlobalValue::InternalLinkage, "__hyc_init_globals",
                                                      m_module.get());
        m_globalInitFunction->setDSOLocal(true);
        FunctionContext ctx;
        ctx.function = m_globalInitFunction;
        ctx.entry = llvm::BasicBlock::Create(m_context, "entry", m_globalInitFunction);
        m_builder->SetInsertPoint(ctx.entry);
        pushLocalScope();
        for (auto *stmt : m_globalInitOrder) {
            emitVarDecl(stmt, ctx);
        }
        m_builder->CreateRetVoid();
        popLocalScope();
        if (m_globalInitFunction && llvm::verifyFunction(*m_globalInitFunction, &llvm::errs())) {
            throw std::runtime_error("verification failed for global initializer");
        }
    }

    for (auto &pair : m_functionMap) {
        llvm::Function *fn = pair.second;
        if (fn && llvm::verifyFunction(*fn, &llvm::errs())) {
            throw std::runtime_error("verification failed for function " + pair.first);
        }
    }

    if (llvm::verifyModule(*m_module, &llvm::errs())) {
        throw std::runtime_error("module verification failed");
    }

    return std::move(m_module);
}

void CodeGenerator::declareGlobals(const Program &program) {
    auto *intTy = llvm::Type::getInt32Ty(m_context);
    for (auto &declPtr : program.declarations) {
        if (declPtr->kind != Decl::Kind::Var) {
            continue;
        }
        auto *varDecl = static_cast<VarDecl *>(declPtr.get());
        auto *stmt = varDecl->statement.get();
        llvm::Constant *init = llvm::ConstantInt::get(intTy, 0, true);
        if (stmt->initializer && stmt->initializer->kind == Expr::Kind::IntegerLiteral) {
            auto *literal = static_cast<IntegerLiteralExpr *>(stmt->initializer.get());
            init = llvm::ConstantInt::get(intTy, literal->value, true);
        }
        auto *global = new llvm::GlobalVariable(*m_module, intTy, false, llvm::GlobalValue::ExternalLinkage, init,
                                                stmt->name);
        global->setDSOLocal(true);
        m_globalValues.emplace(stmt->name, global);
        if (!stmt->initializer || stmt->initializer->kind != Expr::Kind::IntegerLiteral) {
            m_globalInitOrder.push_back(stmt);
        }
    }
}

void CodeGenerator::declareFunctions(const Program &program) {
    auto *intTy = llvm::Type::getInt32Ty(m_context);
    for (auto &declPtr : program.declarations) {
        if (declPtr->kind != Decl::Kind::Function) {
            continue;
        }
        auto *fnDecl = static_cast<FunctionDecl *>(declPtr.get());
        std::vector<llvm::Type *> params(fnDecl->parameters.size(), intTy);
        auto *fnTy = llvm::FunctionType::get(intTy, params, false);
        auto *fn = llvm::Function::Create(fnTy, llvm::GlobalValue::ExternalLinkage, fnDecl->name, m_module.get());
        fn->setDSOLocal(true);
        for (std::size_t i = 0; i < fnDecl->parameters.size(); ++i) {
            fn->getArg(static_cast<unsigned>(i))->setName(fnDecl->parameters[i].name);
        }
        m_functionMap.emplace(fnDecl->name, fn);
    }
}

void CodeGenerator::emitDeclaration(Decl *decl) {
    if (!decl) {
        return;
    }
    if (decl->kind == Decl::Kind::Function) {
        emitFunction(static_cast<FunctionDecl *>(decl));
    }
    // Global variables are handled during declaration and optional init.
}

llvm::AllocaInst *CodeGenerator::createAlloca(FunctionContext &ctx, const std::string &name) {
    llvm::IRBuilder<> allocaBuilder(ctx.entry, ctx.entry->begin());
    return allocaBuilder.CreateAlloca(llvm::Type::getInt32Ty(m_context), nullptr, name);
}

void CodeGenerator::pushLocalScope() { m_localScopes.emplace_back(); }

void CodeGenerator::popLocalScope() {
    if (!m_localScopes.empty()) {
        m_localScopes.pop_back();
    }
}

void CodeGenerator::setLocal(const std::string &name, llvm::AllocaInst *alloca) {
    if (m_localScopes.empty()) {
        pushLocalScope();
    }
    m_localScopes.back()[name] = alloca;
}

llvm::AllocaInst *CodeGenerator::getLocal(const std::string &name) {
    for (auto it = m_localScopes.rbegin(); it != m_localScopes.rend(); ++it) {
        auto found = it->find(name);
        if (found != it->end()) {
            return found->second;
        }
    }
    return nullptr;
}

llvm::Value *CodeGenerator::getVariable(const std::string &name, FunctionContext &ctx) {
    if (auto *local = getLocal(name)) {
        return local;
    }
    auto it = m_globalValues.find(name);
    if (it != m_globalValues.end()) {
        return it->second;
    }
    return nullptr;
}

void CodeGenerator::emitFunction(FunctionDecl *decl) {
    auto it = m_functionMap.find(decl->name);
    if (it == m_functionMap.end()) {
        return;
    }
    auto *fn = it->second;
    FunctionContext ctx;
    ctx.function = fn;
    ctx.entry = llvm::BasicBlock::Create(m_context, "entry", fn);
    m_builder->SetInsertPoint(ctx.entry);
    pushLocalScope();

    for (auto &arg : fn->args()) {
        auto *alloca = createAlloca(ctx, arg.getName().str());
        m_builder->CreateStore(&arg, alloca);
        setLocal(arg.getName().str(), alloca);
    }

    if (decl->name == "main" && m_globalInitFunction) {
        m_builder->CreateCall(m_globalInitFunction, {});
    }

    emitBlock(decl->body.get(), ctx, false);

    if (!ctx.function->back().getTerminator()) {
        m_builder->SetInsertPoint(&ctx.function->back());
        m_builder->CreateRet(llvm::ConstantInt::get(llvm::Type::getInt32Ty(m_context), 0));
    }

    popLocalScope();
}

void CodeGenerator::emitBlock(BlockStmt *block, FunctionContext &ctx, bool createScope) {
    if (!block) {
        return;
    }
    if (createScope) {
        pushLocalScope();
    }
    for (auto &stmt : block->statements) {
        emitStatement(stmt.get(), ctx);
        if (ctx.function->back().getTerminator()) {
            break;
        }
    }
    if (createScope) {
        popLocalScope();
    }
}

void CodeGenerator::emitStatement(Stmt *stmt, FunctionContext &ctx) {
    if (!stmt) {
        return;
    }
    switch (stmt->kind) {
    case Stmt::Kind::VarDecl:
        emitVarDecl(static_cast<VarDeclStmt *>(stmt), ctx);
        break;
    case Stmt::Kind::ExprStmt:
        emitExpr(static_cast<ExprStmt *>(stmt)->expression.get(), ctx);
        break;
    case Stmt::Kind::Return:
        emitReturn(static_cast<ReturnStmt *>(stmt), ctx);
        break;
    case Stmt::Kind::Block:
        emitBlock(static_cast<BlockStmt *>(stmt), ctx);
        break;
    }
}

void CodeGenerator::emitVarDecl(VarDeclStmt *stmt, FunctionContext &ctx) {
    if (!stmt) {
        return;
    }
    if (stmt->isGlobal) {
        if (stmt->initializer && stmt->initializer->kind != Expr::Kind::IntegerLiteral) {
            auto it = m_globalValues.find(stmt->name);
            if (it != m_globalValues.end()) {
                auto *value = emitExpr(stmt->initializer.get(), ctx);
                m_builder->CreateStore(value, it->second);
            }
        }
        return;
    }
    auto *alloca = createAlloca(ctx, stmt->name);
    setLocal(stmt->name, alloca);
    llvm::Value *value = emitExpr(stmt->initializer.get(), ctx);
    m_builder->CreateStore(value, alloca);
}

void CodeGenerator::emitReturn(ReturnStmt *stmt, FunctionContext &ctx) {
    if (!stmt) {
        return;
    }
    llvm::Value *value = nullptr;
    if (stmt->value) {
        value = emitExpr(stmt->value.get(), ctx);
    } else {
        value = llvm::ConstantInt::get(llvm::Type::getInt32Ty(m_context), 0);
    }
    m_builder->CreateRet(value);
}

llvm::Value *CodeGenerator::emitExpr(Expr *expr, FunctionContext &ctx) {
    if (!expr) {
        return llvm::ConstantInt::get(llvm::Type::getInt32Ty(m_context), 0);
    }
    switch (expr->kind) {
    case Expr::Kind::IntegerLiteral: {
        auto *literal = static_cast<IntegerLiteralExpr *>(expr);
        return llvm::ConstantInt::get(llvm::Type::getInt32Ty(m_context), literal->value);
    }
    case Expr::Kind::Identifier: {
        auto *ident = static_cast<IdentifierExpr *>(expr);
        auto *ptr = getVariable(ident->name, ctx);
        if (!ptr) {
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(m_context), 0);
        }
        return m_builder->CreateLoad(llvm::Type::getInt32Ty(m_context), ptr, ident->name);
    }
    case Expr::Kind::Assignment:
        return emitAssignment(static_cast<AssignmentExpr *>(expr), ctx);
    case Expr::Kind::Call:
        return emitCall(static_cast<CallExpr *>(expr), ctx);
    }
    return llvm::ConstantInt::get(llvm::Type::getInt32Ty(m_context), 0);
}

llvm::Value *CodeGenerator::emitAssignment(AssignmentExpr *expr, FunctionContext &ctx) {
    auto *ptr = getVariable(expr->name, ctx);
    if (!ptr) {
        return llvm::ConstantInt::get(llvm::Type::getInt32Ty(m_context), 0);
    }
    auto *value = emitExpr(expr->value.get(), ctx);
    m_builder->CreateStore(value, ptr);
    return value;
}

llvm::Value *CodeGenerator::emitCall(CallExpr *expr, FunctionContext &ctx) {
    if (expr->callee == "Print") {
        auto *fn = m_runtime->getPrintI32();
        llvm::Value *arg = nullptr;
        if (!expr->arguments.empty()) {
            arg = emitExpr(expr->arguments.front().get(), ctx);
        } else {
            arg = llvm::ConstantInt::get(llvm::Type::getInt32Ty(m_context), 0);
        }
        m_builder->CreateCall(fn, {arg});
        return llvm::ConstantInt::get(llvm::Type::getInt32Ty(m_context), 0);
    }
    auto it = m_functionMap.find(expr->callee);
    if (it == m_functionMap.end()) {
        return llvm::ConstantInt::get(llvm::Type::getInt32Ty(m_context), 0);
    }
    std::vector<llvm::Value *> args;
    for (auto &argExpr : expr->arguments) {
        args.push_back(emitExpr(argExpr.get(), ctx));
    }
    return m_builder->CreateCall(it->second, args, expr->callee);
}

} // namespace hyc
