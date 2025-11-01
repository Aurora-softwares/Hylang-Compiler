#include "sema.hpp"

#include <algorithm>

Sema::Sema(DiagnosticsEngine &diag) : diag_(diag) {}

bool Sema::analyze(Program &program) {
    program_ = &program;
    functions_.clear();
    globals_.clear();
    scopes_.clear();
    currentFunction_ = nullptr;

    declareBuiltins();
    gatherFunctions(program);

    for (auto &declPtr : program.declarations) {
        if (!declPtr) {
            continue;
        }
        analyzeTopLevel(*declPtr);
    }

    auto mainIt = functions_.find("main");
    if (mainIt == functions_.end()) {
        diag_.error(1, 1, "program missing Function main()");
        return false;
    }
    if (!mainIt->second.parameters.empty()) {
        diag_.error(1, 1, "Function main() must not take parameters in Hydrogen C v0.1");
    }
    return !diag_.hasErrors();
}

void Sema::declareBuiltins() {
    FunctionSignature printSig;
    printSig.parameters.push_back(SimpleType::Int);
    functions_.emplace("Print", std::move(printSig));
}

void Sema::gatherFunctions(Program &program) {
    for (auto &declPtr : program.declarations) {
        if (!declPtr) {
            continue;
        }
        if (std::holds_alternative<TopLevelDecl::Function>(declPtr->node)) {
            auto &func = *std::get<TopLevelDecl::Function>(declPtr->node).decl;
            if (functions_.count(func.name)) {
                diag_.error(func.loc.line, func.loc.column, "redefinition of function '" + func.name + "'");
                continue;
            }
            FunctionSignature sig;
            for (auto &param : func.parameters) {
                sig.parameters.push_back(param.type);
            }
            functions_.emplace(func.name, std::move(sig));
        }
    }
}

void Sema::analyzeTopLevel(TopLevelDecl &decl) {
    if (std::holds_alternative<TopLevelDecl::VarDeclTop>(decl.node)) {
        auto &var = std::get<TopLevelDecl::VarDeclTop>(decl.node).decl;
        if (globals_.count(var.name)) {
            diag_.error(var.loc.line, var.loc.column, "global variable '" + var.name + "' already declared");
            return;
        }
        globals_.emplace(var.name, &var);
        analyzeExpr(*var.initializer);
    } else if (std::holds_alternative<TopLevelDecl::Function>(decl.node)) {
        auto &func = *std::get<TopLevelDecl::Function>(decl.node).decl;
        analyzeFunction(func);
    }
}

void Sema::analyzeFunction(FunctionDecl &func) {
    currentFunction_ = &func;
    enterScope();
    std::unordered_map<std::string, bool> seen;
    for (auto &param : func.parameters) {
        if (seen.count(param.name) || globals_.count(param.name)) {
            diag_.error(param.loc.line, param.loc.column, "duplicate parameter name '" + param.name + "'");
            continue;
        }
        seen.emplace(param.name, true);
        VarDecl *paramDecl = nullptr;
        scopes_.back().emplace(param.name, paramDecl);
    }

    for (auto &stmt : func.body) {
        if (stmt) {
            analyzeStatement(*stmt);
        }
    }

    exitScope();
    currentFunction_ = nullptr;
}

void Sema::analyzeStatement(Statement &stmt) {
    if (std::holds_alternative<Statement::VarDeclStmt>(stmt.node)) {
        auto &decl = std::get<Statement::VarDeclStmt>(stmt.node).decl;
        analyzeVarDecl(decl);
    } else if (std::holds_alternative<Statement::ReturnStmt>(stmt.node)) {
        auto &ret = std::get<Statement::ReturnStmt>(stmt.node);
        analyzeReturn(ret, stmt.loc);
    } else if (std::holds_alternative<Statement::ExprStmt>(stmt.node)) {
        auto &exprStmt = std::get<Statement::ExprStmt>(stmt.node);
        if (exprStmt.expr) {
            analyzeExpr(*exprStmt.expr);
        }
    }
}

void Sema::analyzeVarDecl(VarDecl &decl) {
    if (!declareVariable(decl.name, &decl, decl.loc)) {
        return;
    }
    if (decl.initializer) {
        analyzeExpr(*decl.initializer);
    }
}

void Sema::analyzeReturn(Statement::ReturnStmt &stmt, const SourceLocation &loc) {
    if (!currentFunction_) {
        diag_.error(loc.line, loc.column, "return statement outside function");
        return;
    }
    if (stmt.hasValue && stmt.value) {
        analyzeExpr(*stmt.value);
    }
}

void Sema::analyzeExpr(Expr &expr) {
    if (std::holds_alternative<Expr::Identifier>(expr.node)) {
        const auto &ident = std::get<Expr::Identifier>(expr.node);
        if (!isVariableDefined(ident.name) && !globals_.count(ident.name)) {
            diag_.error(expr.loc.line, expr.loc.column, "use of undeclared identifier '" + ident.name + "'");
        }
    } else if (std::holds_alternative<Expr::IntegerLiteral>(expr.node)) {
        // ok
    } else if (std::holds_alternative<Expr::Assignment>(expr.node)) {
        auto &assign = std::get<Expr::Assignment>(expr.node);
        if (!isVariableDefined(assign.name) && !globals_.count(assign.name)) {
            diag_.error(expr.loc.line, expr.loc.column, "assignment to undeclared identifier '" + assign.name + "'");
        }
        if (assign.value) {
            analyzeExpr(*assign.value);
        }
    } else if (std::holds_alternative<Expr::Call>(expr.node)) {
        auto &call = std::get<Expr::Call>(expr.node);
        auto it = functions_.find(call.callee);
        if (it == functions_.end()) {
            diag_.error(expr.loc.line, expr.loc.column, "call to unknown function '" + call.callee + "'");
        } else if (call.arguments.size() != it->second.parameters.size()) {
            diag_.error(expr.loc.line, expr.loc.column, "function '" + call.callee + "' expects " +
                                                    std::to_string(it->second.parameters.size()) + " argument(s)");
        }
        for (auto &arg : call.arguments) {
            if (arg) {
                analyzeExpr(*arg);
            }
        }
    }
}

void Sema::enterScope() { scopes_.emplace_back(); }

void Sema::exitScope() {
    if (!scopes_.empty()) {
        scopes_.pop_back();
    }
}

bool Sema::declareVariable(const std::string &name, VarDecl *decl, const SourceLocation &loc) {
    for (const auto &scope : scopes_) {
        if (scope.count(name)) {
            diag_.error(loc.line, loc.column, "redeclaration of variable '" + name + "'");
            return false;
        }
    }
    if (globals_.count(name)) {
        diag_.error(loc.line, loc.column, "redeclaration of global variable '" + name + "'");
        return false;
    }
    if (scopes_.empty()) {
        scopes_.emplace_back();
    }
    scopes_.back().emplace(name, decl);
    return true;
}

bool Sema::isVariableDefined(const std::string &name) const {
    for (auto it = scopes_.rbegin(); it != scopes_.rend(); ++it) {
        if (it->count(name)) {
            return true;
        }
    }
    return false;
}
