#include "codegen.hpp"

#include "winrt.hpp"

#include <unordered_map>
#include <utility>
#include <vector>

#include <llvm/IR/BasicBlock.h>
#include <llvm/IR/Constants.h>
#include <llvm/IR/DerivedTypes.h>
#include <llvm/IR/Function.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>
#include <llvm/IR/Type.h>
#include <llvm/IR/Verifier.h>
#include <llvm/Support/Casting.h>
#include <llvm/Support/raw_ostream.h>

namespace hydrogenc {

struct CodeGenerator::Impl {
    llvm::LLVMContext context;
    std::unique_ptr<llvm::Module> module;
    std::unique_ptr<llvm::IRBuilder<>> builder;
    llvm::Function* current_function = nullptr;

    std::unordered_map<std::string, llvm::GlobalVariable*> globals;
    std::unordered_map<std::string, llvm::Function*> functions;
    std::vector<std::unordered_map<std::string, llvm::Value*>> locals;

    llvm::Type* int_type() const { return llvm::Type::getInt32Ty(context); }
    llvm::Type* void_type() const { return llvm::Type::getVoidTy(context); }

    void push_scope() { locals.emplace_back(); }
    void pop_scope() { locals.pop_back(); }

    llvm::AllocaInst* create_alloca(llvm::Type* type, const std::string& name) {
        llvm::IRBuilder<> tmp(&current_function->getEntryBlock(), current_function->getEntryBlock().begin());
        return tmp.CreateAlloca(type, nullptr, name);
    }

    void bind_local(const std::string& name, llvm::Value* value) {
        locals.back().emplace(name, value);
    }

    llvm::Value* lookup_variable(const std::string& name) {
        for (auto it = locals.rbegin(); it != locals.rend(); ++it) {
            auto found = it->find(name);
            if (found != it->end()) {
                return found->second;
            }
        }
        if (auto global_it = globals.find(name); global_it != globals.end()) {
            return global_it->second;
        }
        return nullptr;
    }

    llvm::Function* lookup_function(const std::string& name) {
        auto it = functions.find(name);
        if (it != functions.end()) {
            return it->second;
        }
        return module->getFunction(name);
    }

    llvm::Value* emit_expression(Expr& expr) {
        switch (expr.kind) {
        case Expr::Kind::Integer: {
            auto& int_expr = static_cast<IntegerExpr&>(expr);
            return llvm::ConstantInt::get(int_type(), int_expr.value, true);
        }
        case Expr::Kind::Identifier: {
            auto& ident = static_cast<IdentifierExpr&>(expr);
            llvm::Value* ptr = lookup_variable(ident.name);
            if (!ptr) {
                return nullptr;
            }
            if (auto* global = llvm::dyn_cast<llvm::GlobalVariable>(ptr)) {
                return builder->CreateLoad(int_type(), global, ident.name);
            }
            return builder->CreateLoad(int_type(), ptr, ident.name);
        }
        case Expr::Kind::Assignment: {
            auto& assign = static_cast<AssignmentExpr&>(expr);
            llvm::Value* ptr = lookup_variable(assign.name);
            if (!ptr) {
                return nullptr;
            }
            llvm::Value* value = emit_expression(*assign.value);
            if (!value) {
                return nullptr;
            }
            if (auto* global = llvm::dyn_cast<llvm::GlobalVariable>(ptr)) {
                builder->CreateStore(value, global);
            } else {
                builder->CreateStore(value, ptr);
            }
            return value;
        }
        case Expr::Kind::Call: {
            auto& call = static_cast<CallExpr&>(expr);
            llvm::Function* callee = lookup_function(call.callee);
            if (!callee) {
                return nullptr;
            }
            std::vector<llvm::Value*> args;
            for (auto& arg : call.arguments) {
                auto* val = emit_expression(*arg);
                if (!val) {
                    return nullptr;
                }
                args.push_back(val);
            }
            return builder->CreateCall(callee, args, call.callee == "Print" ? "" : "calltmp");
        }
        }
        return nullptr;
    }

    void emit_statement(Stmt& stmt) {
        if (builder->GetInsertBlock()->getTerminator()) {
            return;
        }
        switch (stmt.kind) {
        case Stmt::Kind::VarDecl: {
            auto& decl = static_cast<VarDeclStmt&>(stmt);
            auto* alloca = create_alloca(int_type(), decl.name);
            bind_local(decl.name, alloca);
            auto* init = emit_expression(*decl.initializer);
            if (!init) {
                return;
            }
            builder->CreateStore(init, alloca);
            break;
        }
        case Stmt::Kind::Expr: {
            auto& expr_stmt = static_cast<ExprStmt&>(stmt);
            if (expr_stmt.expression) {
                emit_expression(*expr_stmt.expression);
            }
            break;
        }
        case Stmt::Kind::Return: {
            auto& ret = static_cast<ReturnStmt&>(stmt);
            if (ret.expression) {
                auto* value = emit_expression(*ret.expression);
                if (!value) {
                    builder->CreateRet(llvm::ConstantInt::get(int_type(), 0));
                    break;
                }
                builder->CreateRet(value);
            } else {
                builder->CreateRet(llvm::ConstantInt::get(int_type(), 0));
            }
            break;
        }
        case Stmt::Kind::Block: {
            auto& block = static_cast<BlockStmt&>(stmt);
            emit_block(block);
            break;
        }
        }
    }

    void emit_block(BlockStmt& block) {
        push_scope();
        for (auto& stmt : block.statements) {
            emit_statement(*stmt);
            if (builder->GetInsertBlock()->getTerminator()) {
                break;
            }
        }
        pop_scope();
    }

    void emit_function(FunctionDefinition& fn) {
        llvm::Function* function = lookup_function(fn.name);
        current_function = function;
        locals.clear();
        auto* entry = llvm::BasicBlock::Create(context, "entry", function);
        builder->SetInsertPoint(entry);
        push_scope();

        std::size_t idx = 0;
        for (auto& param : fn.parameters) {
            llvm::Argument& arg = *function->getArg(idx++);
            arg.setName(param.name);
            auto* alloca = create_alloca(int_type(), param.name);
            builder->CreateStore(&arg, alloca);
            bind_local(param.name, alloca);
        }

        emit_block(*fn.body);

        if (!builder->GetInsertBlock()->getTerminator()) {
            builder->CreateRet(llvm::ConstantInt::get(int_type(), 0));
        }

        pop_scope();
        current_function = nullptr;
    }

    void emit_global(VarDeclStmt& decl) {
        auto* constant = llvm::ConstantInt::get(int_type(), static_cast<IntegerExpr&>(*decl.initializer).value, true);
        auto* global = new llvm::GlobalVariable(
            *module,
            int_type(),
            false,
            llvm::GlobalValue::ExternalLinkage,
            constant,
            decl.name);
        globals.emplace(decl.name, global);
    }
};

CodeGenerator::CodeGenerator() : impl_(std::make_unique<Impl>()) {}
CodeGenerator::~CodeGenerator() = default;

llvm::LLVMContext& CodeGenerator::context() { return impl_->context; }

std::unique_ptr<llvm::Module> CodeGenerator::generate(const Program& program, const std::string& module_name) {
    impl_->module = std::make_unique<llvm::Module>(module_name, impl_->context);
    impl_->module->setTargetTriple("x86_64-pc-windows-msvc");
    impl_->builder = std::make_unique<llvm::IRBuilder<>>(impl_->context);
    impl_->globals.clear();
    impl_->functions.clear();
    impl_->locals.clear();
    impl_->current_function = nullptr;

    winrt::inject_runtime(*impl_->module);
    if (auto* print_fn = impl_->module->getFunction("Print")) {
        impl_->functions["Print"] = print_fn;
    }

    for (auto& global : program.globals) {
        impl_->emit_global(*global);
    }

    for (auto& fn : program.functions) {
        std::vector<llvm::Type*> param_types(fn->parameters.size(), impl_->int_type());
        auto* fn_type = llvm::FunctionType::get(impl_->int_type(), param_types, false);
        auto* function = llvm::Function::Create(fn_type, llvm::GlobalValue::ExternalLinkage, fn->name, impl_->module.get());
        impl_->functions.emplace(fn->name, function);
    }

    for (auto& fn : program.functions) {
        impl_->emit_function(*fn);
    }

    llvm::verifyModule(*impl_->module, &llvm::errs());
    return std::move(impl_->module);
}

} // namespace hydrogenc
