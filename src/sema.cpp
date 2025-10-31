#include "sema.hpp"

#include <algorithm>

namespace hydrogenc {

Sema::Sema(DiagnosticEngine& diag) : diag_(diag) {
    declare_builtin_functions();
}

void Sema::declare_builtin_functions() {
    FunctionInfo print;
    print.name = "Print";
    print.return_type = Type::Int();
    print.is_builtin = true;
    print.location = {0, 0};
    Param param;
    param.name = "value";
    param.type = Type::Int();
    param.location = {0, 0};
    print.parameters.push_back(param);
    functions_.emplace(print.name, print);
}

bool Sema::analyze(Program& program) {
    bool ok = declare_globals(program);
    ok = declare_functions(program) && ok;
    if (!functions_.count("main")) {
        diag_.report({DiagnosticLevel::Error, {0, 0}, "missing entry point 'Function main()'", 4});
        ok = false;
    }
    for (auto& global : program.globals) {
        ok = analyze_global(*global) && ok;
    }
    for (auto& fn : program.functions) {
        ok = analyze_function(*fn) && ok;
    }
    return ok && !diag_.has_error();
}

bool Sema::declare_globals(Program& program) {
    bool ok = true;
    for (auto& decl : program.globals) {
        if (globals_.count(decl->name)) {
            diag_.report({DiagnosticLevel::Error, decl->location, "duplicate global variable", decl->name.size()});
            ok = false;
            continue;
        }
        globals_.emplace(decl->name, VariableInfo{decl->name, decl->type, decl->location});
    }
    return ok;
}

bool Sema::declare_functions(Program& program) {
    bool ok = true;
    for (auto& fn : program.functions) {
        if (functions_.count(fn->name)) {
            diag_.report({DiagnosticLevel::Error, fn->location, "duplicate function", fn->name.size()});
            ok = false;
            continue;
        }
        FunctionInfo info;
        info.name = fn->name;
        info.return_type = Type::Int();
        info.location = fn->location;
        info.parameters = fn->parameters;
        functions_.emplace(info.name, info);
    }
    return ok;
}

bool Sema::analyze_global(VarDeclStmt& decl) {
    Type init_type;
    std::vector<VariableInfo> scope;
    if (!analyze_expression(*decl.initializer, scope, init_type)) {
        return false;
    }
    if (!init_type.is_int()) {
        diag_.report({DiagnosticLevel::Error, decl.location, "global initializers must be Int", decl.name.size()});
        return false;
    }
    if (decl.initializer->kind != Expr::Kind::Integer) {
        diag_.report({DiagnosticLevel::Error, decl.location, "global initializer must be constant integer", decl.name.size()});
        return false;
    }
    decl.type = Type::Int();
    return true;
}

bool Sema::analyze_function(FunctionDefinition& fn) {
    auto it = functions_.find(fn.name);
    if (it == functions_.end()) {
        return false;
    }
    std::vector<VariableInfo> scope;
    for (auto& param : fn.parameters) {
        if (std::any_of(scope.begin(), scope.end(), [&](const VariableInfo& v) { return v.name == param.name; })) {
            diag_.report({DiagnosticLevel::Error, param.location, "duplicate parameter", param.name.size()});
            return false;
        }
        scope.push_back({param.name, param.type, param.location});
    }
    if (!fn.body) {
        diag_.report({DiagnosticLevel::Error, fn.location, "function missing body", fn.name.size()});
        return false;
    }
    if (fn.name == "main" && !fn.parameters.empty()) {
        diag_.report({DiagnosticLevel::Error, fn.location, "main must not take parameters", fn.name.size()});
        return false;
    }
    if (!analyze_block(*fn.body, scope)) {
        return false;
    }
    // Ensure an implicit return is okay
    return true;
}

bool Sema::analyze_block(BlockStmt& block, std::vector<VariableInfo>& scope) {
    std::size_t original_size = scope.size();
    for (auto& stmt : block.statements) {
        if (!analyze_statement(*stmt, scope)) {
            return false;
        }
    }
    scope.resize(original_size);
    return true;
}

bool Sema::analyze_statement(Stmt& stmt, std::vector<VariableInfo>& scope) {
    switch (stmt.kind) {
    case Stmt::Kind::VarDecl: {
        auto& decl = static_cast<VarDeclStmt&>(stmt);
        if (resolve_variable(decl.name, scope)) {
            diag_.report({DiagnosticLevel::Error, decl.location, "variable already declared", decl.name.size()});
            return false;
        }
        Type init_type;
        if (!analyze_expression(*decl.initializer, scope, init_type)) {
            return false;
        }
        if (!init_type.is_int()) {
            diag_.report({DiagnosticLevel::Error, decl.location, "initializer must be Int", decl.name.size()});
            return false;
        }
        scope.push_back({decl.name, decl.type, decl.location});
        return true;
    }
    case Stmt::Kind::Expr: {
        auto& expr_stmt = static_cast<ExprStmt&>(stmt);
        if (!expr_stmt.expression) {
            return true;
        }
        Type expr_type;
        return analyze_expression(*expr_stmt.expression, scope, expr_type);
    }
    case Stmt::Kind::Return: {
        auto& ret = static_cast<ReturnStmt&>(stmt);
        if (ret.expression) {
            Type expr_type;
            if (!analyze_expression(*ret.expression, scope, expr_type)) {
                return false;
            }
            if (!expr_type.is_int()) {
                diag_.report({DiagnosticLevel::Error, ret.location, "return type must be Int", 6});
                return false;
            }
        }
        return true;
    }
    case Stmt::Kind::Block: {
        auto& inner = static_cast<BlockStmt&>(stmt);
        return analyze_block(inner, scope);
    }
    }
    return false;
}

bool Sema::analyze_expression(Expr& expr, std::vector<VariableInfo>& scope, Type& out_type) {
    switch (expr.kind) {
    case Expr::Kind::Identifier: {
        auto& ident = static_cast<IdentifierExpr&>(expr);
        if (auto* var = resolve_variable(ident.name, scope)) {
            out_type = var->type;
            expr.resolved_type = var->type;
            return true;
        }
        if (globals_.count(ident.name)) {
            out_type = globals_[ident.name].type;
            expr.resolved_type = out_type;
            return true;
        }
        diag_.report({DiagnosticLevel::Error, ident.location, "unknown identifier", ident.name.size()});
        return false;
    }
    case Expr::Kind::Integer: {
        out_type = Type::Int();
        expr.resolved_type = out_type;
        return true;
    }
    case Expr::Kind::Call: {
        auto& call = static_cast<CallExpr&>(expr);
        auto* fn = resolve_function(call.callee);
        if (!fn) {
            diag_.report({DiagnosticLevel::Error, call.location, "unknown function", call.callee.size()});
            return false;
        }
        if (call.arguments.size() != fn->parameters.size()) {
            diag_.report({DiagnosticLevel::Error, call.location, "wrong number of arguments", call.callee.size()});
            return false;
        }
        for (std::size_t i = 0; i < call.arguments.size(); ++i) {
            Type arg_type;
            if (!analyze_expression(*call.arguments[i], scope, arg_type)) {
                return false;
            }
            if (!arg_type.is_int()) {
                diag_.report({DiagnosticLevel::Error, call.arguments[i]->location, "argument must be Int", 1});
                return false;
            }
        }
        out_type = fn->return_type;
        expr.resolved_type = out_type;
        return true;
    }
    case Expr::Kind::Assignment: {
        auto& assign = static_cast<AssignmentExpr&>(expr);
        if (auto* var = resolve_variable(assign.name, scope)) {
            Type rhs_type;
            if (!analyze_expression(*assign.value, scope, rhs_type)) {
                return false;
            }
            if (!rhs_type.is_int()) {
                diag_.report({DiagnosticLevel::Error, assign.location, "assignment requires Int", assign.name.size()});
                return false;
            }
            out_type = var->type;
            expr.resolved_type = out_type;
            return true;
        }
        if (globals_.count(assign.name)) {
            Type rhs_type;
            if (!analyze_expression(*assign.value, scope, rhs_type)) {
                return false;
            }
            if (!rhs_type.is_int()) {
                diag_.report({DiagnosticLevel::Error, assign.location, "assignment requires Int", assign.name.size()});
                return false;
            }
            out_type = globals_[assign.name].type;
            expr.resolved_type = out_type;
            return true;
        }
        diag_.report({DiagnosticLevel::Error, assign.location, "unknown variable", assign.name.size()});
        return false;
    }
    }
    return false;
}

VariableInfo* Sema::resolve_variable(const std::string& name, std::vector<VariableInfo>& scope) {
    for (auto it = scope.rbegin(); it != scope.rend(); ++it) {
        if (it->name == name) {
            return &*it;
        }
    }
    if (auto it = globals_.find(name); it != globals_.end()) {
        return &it->second;
    }
    return nullptr;
}

FunctionInfo* Sema::resolve_function(const std::string& name) {
    if (auto it = functions_.find(name); it != functions_.end()) {
        return &it->second;
    }
    return nullptr;
}

} // namespace hydrogenc
