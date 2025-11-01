#include "codegen.hpp"

#include <optional>

#include <llvm/IR/Constants.h>
#include <llvm/IR/Function.h>
#include <llvm/IR/Verifier.h>
#include <llvm/Support/raw_ostream.h>

#include "winrt.hpp"

namespace {
std::optional<int> evalConstInt(Expr &expr) {
    if (std::holds_alternative<Expr::IntegerLiteral>(expr.node)) {
        return std::get<Expr::IntegerLiteral>(expr.node).value;
    }
    return std::nullopt;
}
}

CodeGenerator::CodeGenerator(DiagnosticsEngine &diag, const Sema &sema, std::string moduleName)
    : diag_(diag), sema_(sema), module_(std::make_unique<llvm::Module>(std::move(moduleName), context_)), builder_(context_) {
    module_->setTargetTriple("x86_64-pc-windows-msvc");
}

bool CodeGenerator::generate(Program &program) {
    winrt::getOrCreatePrintFunction(*module_);
    winrt::getStdHandleDecl(*module_);
    winrt::getWriteFileDecl(*module_);

    // Create function prototypes
    for (auto &declPtr : program.declarations) {
        if (!declPtr) {
            continue;
        }
        if (std::holds_alternative<TopLevelDecl::Function>(declPtr->node)) {
            auto &func = *std::get<TopLevelDecl::Function>(declPtr->node).decl;
            if (func.name == "Print") {
                continue;
            }
            auto *returnTy = llvm::Type::getInt32Ty(context_);
            std::vector<llvm::Type *> paramTys(func.parameters.size(), llvm::Type::getInt32Ty(context_));
            auto *fnTy = llvm::FunctionType::get(returnTy, paramTys, false);
            auto *fn = llvm::Function::Create(fnTy, llvm::Function::ExternalLinkage, func.name, module_.get());
            std::size_t idx = 0;
            for (auto &param : func.parameters) {
                fn->getArg(idx)->setName(param.name);
                ++idx;
            }
            functions_[func.name] = fn;
        }
    }

    // Emit globals
    for (auto &[name, decl] : sema_.globals()) {
        emitGlobal(*decl);
    }

    // Emit function bodies
    for (auto &declPtr : program.declarations) {
        if (!declPtr) {
            continue;
        }
        if (std::holds_alternative<TopLevelDecl::Function>(declPtr->node)) {
            auto &func = *std::get<TopLevelDecl::Function>(declPtr->node).decl;
            if (func.name == "Print") {
                continue;
            }
            emitFunction(func);
        }
    }

    if (llvm::verifyModule(*module_, &llvm::errs())) {
        diag_.error(1, 1, "generated module is invalid");
        return false;
    }
    return true;
}

llvm::Type *CodeGenerator::toLLVMType(SimpleType type) {
    switch (type) {
    case SimpleType::Int:
        return llvm::Type::getInt32Ty(context_);
    }
    return llvm::Type::getInt32Ty(context_);
}

void CodeGenerator::emitGlobal(VarDecl &decl) {
    auto *type = toLLVMType(decl.type);
    llvm::Constant *init = nullptr;
    if (decl.initializer) {
        if (auto value = evalConstInt(*decl.initializer)) {
            init = llvm::ConstantInt::get(type, *value, true);
        }
    }
    if (!init) {
        init = llvm::ConstantInt::get(type, 0);
    }
    auto *global = new llvm::GlobalVariable(*module_, type, false, llvm::GlobalValue::ExternalLinkage, init, decl.name);
    globals_[decl.name] = global;
}

void CodeGenerator::emitFunction(FunctionDecl &decl) {
    currentFunction_ = &decl;
    currentLLVMFunction_ = functions_[decl.name];
    if (!currentLLVMFunction_) {
        return;
    }

    auto *entry = llvm::BasicBlock::Create(context_, "entry", currentLLVMFunction_);
    builder_.SetInsertPoint(entry);

    scopeStack_.clear();
    scopeStack_.emplace_back();

    std::size_t idx = 0;
    for (auto &param : decl.parameters) {
        auto *alloca = createEntryAlloca(param.name);
        builder_.CreateStore(currentLLVMFunction_->getArg(idx), alloca);
        scopeStack_.back().emplace(param.name, alloca);
        ++idx;
    }

    for (auto &stmt : decl.body) {
        if (stmt) {
            emitStatement(*stmt);
        }
    }

    if (!builder_.GetInsertBlock()->getTerminator()) {
        builder_.CreateRet(llvm::ConstantInt::get(llvm::Type::getInt32Ty(context_), 0));
    }

    currentFunction_ = nullptr;
    currentLLVMFunction_ = nullptr;
}

llvm::AllocaInst *CodeGenerator::createEntryAlloca(const std::string &name) {
    llvm::IRBuilder<> tmp(&currentLLVMFunction_->getEntryBlock(), currentLLVMFunction_->getEntryBlock().begin());
    return tmp.CreateAlloca(llvm::Type::getInt32Ty(context_), nullptr, name);
}

void CodeGenerator::emitStatement(Statement &stmt) {
    if (std::holds_alternative<Statement::VarDeclStmt>(stmt.node)) {
        auto &decl = std::get<Statement::VarDeclStmt>(stmt.node).decl;
        emitVarDecl(decl);
    } else if (std::holds_alternative<Statement::ReturnStmt>(stmt.node)) {
        emitReturn(std::get<Statement::ReturnStmt>(stmt.node));
    } else if (std::holds_alternative<Statement::ExprStmt>(stmt.node)) {
        auto &exprStmt = std::get<Statement::ExprStmt>(stmt.node);
        if (exprStmt.expr) {
            emitExpr(*exprStmt.expr);
        }
    }
}

void CodeGenerator::emitVarDecl(VarDecl &decl) {
    auto *alloca = createEntryAlloca(decl.name);
    scopeStack_.back().emplace(decl.name, alloca);
    llvm::Value *init = nullptr;
    if (decl.initializer) {
        init = emitExpr(*decl.initializer);
    }
    if (!init) {
        init = llvm::ConstantInt::get(llvm::Type::getInt32Ty(context_), 0);
    }
    builder_.CreateStore(init, alloca);
}

void CodeGenerator::emitReturn(Statement::ReturnStmt &stmt) {
    llvm::Value *value = llvm::ConstantInt::get(llvm::Type::getInt32Ty(context_), 0);
    if (stmt.hasValue && stmt.value) {
        if (auto *val = emitExpr(*stmt.value)) {
            value = val;
        }
    }
    builder_.CreateRet(value);
    auto *after = llvm::BasicBlock::Create(context_, "after_return", currentLLVMFunction_);
    builder_.SetInsertPoint(after);
}

llvm::Value *CodeGenerator::getVariable(const std::string &name) {
    for (auto it = scopeStack_.rbegin(); it != scopeStack_.rend(); ++it) {
        auto found = it->find(name);
        if (found != it->end()) {
            return found->second;
        }
    }
    auto globalIt = globals_.find(name);
    if (globalIt != globals_.end()) {
        return globalIt->second;
    }
    return nullptr;
}

llvm::Value *CodeGenerator::emitAssignment(Expr::Assignment &assign) {
    auto *ptr = getVariable(assign.name);
    if (!ptr) {
        return llvm::ConstantInt::get(llvm::Type::getInt32Ty(context_), 0);
    }
    auto *value = emitExpr(*assign.value);
    if (!value) {
        value = llvm::ConstantInt::get(llvm::Type::getInt32Ty(context_), 0);
    }
    builder_.CreateStore(value, ptr);
    return builder_.CreateLoad(llvm::Type::getInt32Ty(context_), ptr, assign.name.c_str());
}

llvm::Value *CodeGenerator::emitExpr(Expr &expr) {
    if (std::holds_alternative<Expr::Identifier>(expr.node)) {
        auto &ident = std::get<Expr::Identifier>(expr.node);
        auto *ptr = getVariable(ident.name);
        if (!ptr) {
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(context_), 0);
        }
        return builder_.CreateLoad(llvm::Type::getInt32Ty(context_), ptr, ident.name.c_str());
    }
    if (std::holds_alternative<Expr::IntegerLiteral>(expr.node)) {
        auto &literal = std::get<Expr::IntegerLiteral>(expr.node);
        return llvm::ConstantInt::get(llvm::Type::getInt32Ty(context_), literal.value, true);
    }
    if (std::holds_alternative<Expr::Assignment>(expr.node)) {
        auto &assign = std::get<Expr::Assignment>(expr.node);
        return emitAssignment(assign);
    }
    if (std::holds_alternative<Expr::Call>(expr.node)) {
        auto &call = std::get<Expr::Call>(expr.node);
        std::vector<llvm::Value *> args;
        for (auto &arg : call.arguments) {
            args.push_back(emitExpr(*arg));
        }
        if (call.callee == "Print") {
            auto *printFn = winrt::getOrCreatePrintFunction(*module_);
            builder_.CreateCall(printFn, args);
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(context_), 0);
        }
        auto it = functions_.find(call.callee);
        if (it == functions_.end()) {
            return llvm::ConstantInt::get(llvm::Type::getInt32Ty(context_), 0);
        }
        return builder_.CreateCall(it->second, args, call.callee);
    }
    return llvm::ConstantInt::get(llvm::Type::getInt32Ty(context_), 0);
}
