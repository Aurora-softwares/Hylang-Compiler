#include "sema.hpp"

#include <algorithm>

namespace hyc {

SemanticAnalyzer::SemanticAnalyzer(Diagnostics& diags) : diags_(diags) {
    FunctionInfo print;
    print.params = {SimpleTypeKind::Int};
    print.result = SimpleTypeKind::Int;
    print.defined = true;
    functions_.emplace("Print", print);
}

bool SemanticAnalyzer::Scope::declare(const std::string& name,
                                      VariableInfo info) {
    return variables_.emplace(name, info).second;
}

SemanticAnalyzer::VariableInfo*
SemanticAnalyzer::Scope::lookup(const std::string& name) {
    auto it = variables_.find(name);
    if (it == variables_.end()) {
        return nullptr;
    }
    return &it->second;
}

void SemanticAnalyzer::push_scope() { scope_stack_.emplace_back(); }

void SemanticAnalyzer::pop_scope() {
    if (!scope_stack_.empty()) {
        scope_stack_.pop_back();
    }
}

SemanticAnalyzer::VariableInfo*
SemanticAnalyzer::lookup_variable(const std::string& name) {
    for (auto it = scope_stack_.rbegin(); it != scope_stack_.rend(); ++it) {
        if (auto* info = it->lookup(name)) {
            return info;
        }
    }
    return nullptr;
}

bool SemanticAnalyzer::declare_variable(const std::string& name,
                                        VariableInfo info) {
    if (scope_stack_.empty()) {
        push_scope();
    }
    Scope& scope = scope_stack_.back();
    if (!scope.declare(name, info)) {
        diags_.error(info.loc, "redefinition of variable '" + name + "'");
        return false;
    }
    return true;
}

SemanticAnalyzer::FunctionInfo*
SemanticAnalyzer::lookup_function(const std::string& name) {
    auto it = functions_.find(name);
    if (it == functions_.end()) {
        return nullptr;
    }
    return &it->second;
}

bool SemanticAnalyzer::declare_function(const std::string& name,
                                        FunctionInfo info) {
    auto [it, inserted] = functions_.emplace(name, info);
    if (!inserted) {
        diags_.error(info.loc, "redefinition of function '" + name + "'");
        return false;
    }
    return true;
}

bool SemanticAnalyzer::analyze(Program& program) {
    push_scope(); // global scope

    // First pass: function declarations
    for (auto& decl_ptr : program.decls) {
        if (decl_ptr->kind == Decl::Kind::Function) {
            auto* func = static_cast<FunctionDecl*>(decl_ptr.get());
            FunctionInfo info;
            info.loc = func->loc;
            info.decl = func;
            info.result = SimpleTypeKind::Int;
            for (const auto& param : func->params) {
                info.params.push_back(SimpleTypeKind::Int);
            }
            if (!declare_function(func->name, info)) {
                continue;
            }
            if (func->name == "main") {
                has_main_ = true;
                if (!func->params.empty()) {
                    diags_.error(func->loc, "main must not take parameters");
                }
            }
        }
    }

    bool ok = true;
    for (auto& decl_ptr : program.decls) {
        if (!check_decl(*decl_ptr)) {
            ok = false;
        }
    }

    if (!has_main_) {
        diags_.error(SourceLocation{"<program>", 1, 1},
                     "missing entry point Function main()");
        ok = false;
    }

    return ok && !diags_.has_errors();
}

bool SemanticAnalyzer::check_decl(Decl& decl) {
    switch (decl.kind) {
    case Decl::Kind::GlobalVar:
        return check_global_var(static_cast<GlobalVarDecl&>(decl));
    case Decl::Kind::Function:
        return check_function(static_cast<FunctionDecl&>(decl));
    }
    return false;
}

bool SemanticAnalyzer::check_function(FunctionDecl& func) {
    FunctionInfo* info = lookup_function(func.name);
    if (!info) {
        diags_.error(func.loc, "undeclared function '" + func.name + "'");
        return false;
    }
    if (info->defined) {
        diags_.error(func.loc, "duplicate definition of function '" + func.name +
                                 "'");
        return false;
    }
    info->defined = true;

    push_scope();
    bool ok = true;
    for (std::size_t i = 0; i < func.params.size(); ++i) {
        const auto& param = func.params[i];
        VariableInfo vinfo{SimpleTypeKind::Int, param.loc};
        if (!declare_variable(param.name, vinfo)) {
            ok = false;
        }
    }

    for (auto& stmt : func.body) {
        if (!check_statement(*stmt, info->result)) {
            ok = false;
        }
    }
    pop_scope();
    return ok;
}

bool SemanticAnalyzer::check_global_var(GlobalVarDecl& var) {
    VariableInfo info{SimpleTypeKind::Int, var.loc};
    if (!declare_variable(var.name, info)) {
        return false;
    }
    if (!var.initializer) {
        diags_.error(var.loc, "global variable requires initializer");
        return false;
    }
    auto type = check_expr(*var.initializer);
    if (!type || *type != SimpleTypeKind::Int) {
        diags_.error(var.initializer->loc,
                     "initializer for global variable must be Int");
        return false;
    }
    return true;
}

bool SemanticAnalyzer::check_statement(Stmt& stmt,
                                       SimpleTypeKind expected_return) {
    switch (stmt.kind) {
    case Stmt::Kind::Var:
        return check_var_decl(static_cast<VarDeclStmt&>(stmt));
    case Stmt::Kind::Expr:
        return check_expr_stmt(static_cast<ExprStmt&>(stmt));
    case Stmt::Kind::Return:
        return check_return(static_cast<ReturnStmt&>(stmt), expected_return);
    }
    return false;
}

bool SemanticAnalyzer::check_var_decl(VarDeclStmt& var) {
    VariableInfo info{SimpleTypeKind::Int, var.loc};
    if (!declare_variable(var.name, info)) {
        return false;
    }
    if (!var.initializer) {
        diags_.error(var.loc, "variable requires initializer");
        return false;
    }
    auto type = check_expr(*var.initializer);
    if (!type || *type != SimpleTypeKind::Int) {
        diags_.error(var.initializer->loc, "initializer type mismatch");
        return false;
    }
    return true;
}

bool SemanticAnalyzer::check_return(ReturnStmt& stmt,
                                    SimpleTypeKind expected_return) {
    if (!stmt.expression) {
        return true;
    }
    auto type = check_expr(*stmt.expression);
    if (!type) {
        return false;
    }
    if (*type != expected_return) {
        diags_.error(stmt.loc, "return type mismatch");
        return false;
    }
    return true;
}

bool SemanticAnalyzer::check_expr_stmt(ExprStmt& stmt) {
    if (!stmt.expression) {
        diags_.error(stmt.loc, "expected expression");
        return false;
    }
    return check_expr(*stmt.expression).has_value();
}

std::optional<SimpleTypeKind> SemanticAnalyzer::check_expr(Expr& expr) {
    switch (expr.kind) {
    case Expr::Kind::Identifier: {
        auto& ident = static_cast<IdentifierExpr&>(expr);
        auto* info = lookup_variable(ident.name);
        if (!info) {
            diags_.error(expr.loc, "unknown identifier '" + ident.name + "'");
            return std::nullopt;
        }
        return info->type;
    }
    case Expr::Kind::Integer:
        return SimpleTypeKind::Int;
    case Expr::Kind::Call: {
        auto& call = static_cast<CallExpr&>(expr);
        FunctionInfo* func = lookup_function(call.callee);
        if (!func) {
            diags_.error(expr.loc, "unknown function '" + call.callee + "'");
            return std::nullopt;
        }
        if (call.args.size() != func->params.size()) {
            diags_.error(expr.loc, "function '" + call.callee +
                                        "' called with wrong number of arguments");
            return std::nullopt;
        }
        for (std::size_t i = 0; i < call.args.size(); ++i) {
            if (!call.args[i]) {
                return std::nullopt;
            }
            auto type = check_expr(*call.args[i]);
            if (!type) {
                return std::nullopt;
            }
            if (*type != func->params[i]) {
                diags_.error(call.args[i]->loc,
                             "argument type mismatch for parameter " +
                                 std::to_string(i + 1));
                return std::nullopt;
            }
        }
        return func->result;
    }
    case Expr::Kind::Assignment: {
        auto& assign = static_cast<AssignmentExpr&>(expr);
        auto* info = lookup_variable(assign.target);
        if (!info) {
            diags_.error(expr.loc,
                         "assignment to undeclared variable '" + assign.target +
                             "'");
            return std::nullopt;
        }
        if (!assign.value) {
            return std::nullopt;
        }
        auto type = check_expr(*assign.value);
        if (!type) {
            return std::nullopt;
        }
        if (*type != info->type) {
            diags_.error(assign.value->loc, "assignment type mismatch");
            return std::nullopt;
        }
        return info->type;
    }
    }
    return std::nullopt;
}

} // namespace hyc
