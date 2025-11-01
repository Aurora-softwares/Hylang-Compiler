#include "sema.hpp"

#include <algorithm>
#include <unordered_set>

namespace hyc {

Sema::Sema(Diagnostics &diag, std::string source) : m_diag(diag), m_source(std::move(source)) {
    std::size_t start = 0;
    while (start < m_source.size()) {
        auto end = m_source.find('\n', start);
        if (end == std::string::npos) {
            end = m_source.size();
        }
        m_lines.emplace_back(m_source.substr(start, end - start));
        start = end + 1;
    }
    if (m_lines.empty()) {
        m_lines.emplace_back("");
    }
    FunctionInfo printInfo;
    printInfo.name = "Print";
    printInfo.paramCount = 1;
    printInfo.decl = nullptr;
    printInfo.isBuiltin = true;
    m_functions.emplace(printInfo.name, printInfo);
}

std::string Sema::lineText(unsigned line) const {
    if (line == 0 || line > m_lines.size()) {
        return "";
    }
    return m_lines[line - 1];
}

void Sema::pushScope() { m_scopes.emplace_back(); }

void Sema::popScope() {
    if (!m_scopes.empty()) {
        m_scopes.pop_back();
    }
}

bool Sema::declareVariable(const std::string &name, const SourceLocation &loc) {
    if (variableExists(name)) {
        m_diag.error(loc, lineText(loc.line), loc.column - 1, static_cast<unsigned>(name.size()),
                     "redeclaration of variable '" + name + "'");
        return false;
    }
    if (m_scopes.empty()) {
        pushScope();
    }
    m_scopes.back().variables.emplace(name, loc);
    return true;
}

bool Sema::variableExists(const std::string &name) const {
    for (auto it = m_scopes.rbegin(); it != m_scopes.rend(); ++it) {
        if (it->variables.count(name)) {
            return true;
        }
    }
    return m_globalVariables.count(name) != 0;
}

bool Sema::analyze(Program &program) {
    for (auto &declPtr : program.declarations) {
        if (declPtr->kind == Decl::Kind::Var) {
            auto *varDecl = static_cast<VarDecl *>(declPtr.get());
            auto *stmt = varDecl->statement.get();
            if (m_globalVariables.count(stmt->name) != 0) {
                m_diag.error(stmt->location, lineText(stmt->location.line), stmt->location.column - 1,
                             static_cast<unsigned>(stmt->name.size()),
                             "redeclaration of global variable '" + stmt->name + "'");
            } else if (m_functions.count(stmt->name) != 0) {
                m_diag.error(stmt->location, lineText(stmt->location.line), stmt->location.column - 1,
                             static_cast<unsigned>(stmt->name.size()),
                             "identifier '" + stmt->name + "' already used for a function");
            } else {
                m_globalVariables.emplace(stmt->name, stmt->location);
            }
        } else if (declPtr->kind == Decl::Kind::Function) {
            auto *funcDecl = static_cast<FunctionDecl *>(declPtr.get());
            if (m_functions.count(funcDecl->name) != 0) {
                m_diag.error(funcDecl->location, lineText(funcDecl->location.line), funcDecl->location.column - 1,
                             static_cast<unsigned>(funcDecl->name.size()),
                             "redefinition of function '" + funcDecl->name + "'");
                continue;
            }
            FunctionInfo info;
            info.name = funcDecl->name;
            info.paramCount = funcDecl->parameters.size();
            info.decl = funcDecl;
            info.isBuiltin = false;
            m_functions.emplace(info.name, info);
            if (funcDecl->name == "main" && funcDecl->parameters.empty()) {
                m_hasMain = true;
            }
            std::unordered_set<std::string> paramNames;
            for (const auto &param : funcDecl->parameters) {
                if (!paramNames.insert(param.name).second) {
                    m_diag.error(param.location, lineText(param.location.line), param.location.column - 1,
                                 static_cast<unsigned>(param.name.size()),
                                 "duplicate parameter name '" + param.name + "'");
                }
                if (m_globalVariables.count(param.name) != 0) {
                    m_diag.error(param.location, lineText(param.location.line), param.location.column - 1,
                                 static_cast<unsigned>(param.name.size()),
                                 "parameter '" + param.name + "' conflicts with global variable");
                }
            }
        }
    }

    if (!m_hasMain) {
        SourceLocation dummy{"<input>", 1, 1};
        m_diag.error(dummy, lineText(1), 0, 1, "missing entry point Function main()");
    }

    for (auto &declPtr : program.declarations) {
        checkDeclaration(declPtr.get());
    }

    return !m_diag.hasErrors();
}

bool Sema::checkDeclaration(Decl *decl) {
    if (!decl) {
        return false;
    }
    switch (decl->kind) {
    case Decl::Kind::Var:
        return checkVarDecl(static_cast<VarDecl *>(decl)->statement.get());
    case Decl::Kind::Function:
        return checkFunction(static_cast<FunctionDecl *>(decl));
    }
    return false;
}

bool Sema::checkFunction(FunctionDecl *decl) {
    if (!decl || !decl->body) {
        return false;
    }
    pushScope();
    for (const auto &param : decl->parameters) {
        declareVariable(param.name, param.location);
    }
    bool ok = checkBlock(decl->body.get(), /*createScope=*/false);
    popScope();
    return ok;
}

bool Sema::checkBlock(BlockStmt *block, bool createScope) {
    if (!block) {
        return false;
    }
    if (createScope) {
        pushScope();
    }
    bool ok = true;
    for (auto &stmt : block->statements) {
        ok &= checkStatement(stmt.get());
    }
    if (createScope) {
        popScope();
    }
    return ok;
}

bool Sema::checkStatement(Stmt *stmt) {
    if (!stmt) {
        return false;
    }
    switch (stmt->kind) {
    case Stmt::Kind::VarDecl:
        return checkVarDecl(static_cast<VarDeclStmt *>(stmt));
    case Stmt::Kind::ExprStmt:
        return checkExpr(static_cast<ExprStmt *>(stmt)->expression.get());
    case Stmt::Kind::Return:
        return checkReturn(static_cast<ReturnStmt *>(stmt));
    case Stmt::Kind::Block:
        return checkBlock(static_cast<BlockStmt *>(stmt));
    }
    return false;
}

bool Sema::checkVarDecl(VarDeclStmt *stmt) {
    if (!stmt) {
        return false;
    }
    if (!stmt->isGlobal) {
        declareVariable(stmt->name, stmt->location);
    }
    if (stmt->initializer) {
        return checkExpr(stmt->initializer.get());
    }
    return true;
}

bool Sema::checkReturn(ReturnStmt *stmt) {
    if (!stmt) {
        return false;
    }
    if (stmt->value) {
        return checkExpr(stmt->value.get());
    }
    return true;
}

bool Sema::checkExpr(Expr *expr) {
    if (!expr) {
        return false;
    }
    switch (expr->kind) {
    case Expr::Kind::IntegerLiteral:
        return true;
    case Expr::Kind::Identifier: {
        auto *ident = static_cast<IdentifierExpr *>(expr);
        if (!variableExists(ident->name)) {
            m_diag.error(ident->location, lineText(ident->location.line), ident->location.column - 1,
                         static_cast<unsigned>(ident->name.size()),
                         "use of undeclared identifier '" + ident->name + "'");
            return false;
        }
        return true;
    }
    case Expr::Kind::Assignment: {
        auto *assign = static_cast<AssignmentExpr *>(expr);
        if (!variableExists(assign->name)) {
            m_diag.error(assign->location, lineText(assign->location.line), assign->location.column - 1,
                         static_cast<unsigned>(assign->name.size()),
                         "cannot assign to undeclared variable '" + assign->name + "'");
            return false;
        }
        return checkExpr(assign->value.get());
    }
    case Expr::Kind::Call: {
        auto *call = static_cast<CallExpr *>(expr);
        auto it = m_functions.find(call->callee);
        if (it == m_functions.end()) {
            m_diag.error(call->location, lineText(call->location.line), call->location.column - 1,
                         static_cast<unsigned>(call->callee.size()),
                         "call to unknown function '" + call->callee + "'");
            return false;
        }
        if (call->arguments.size() != it->second.paramCount) {
            m_diag.error(call->location, lineText(call->location.line), call->location.column - 1,
                         static_cast<unsigned>(call->callee.size()),
                         "function '" + call->callee + "' expects " + std::to_string(it->second.paramCount) +
                             " argument(s)");
            return false;
        }
        bool ok = true;
        for (auto &arg : call->arguments) {
            ok &= checkExpr(arg.get());
        }
        return ok;
    }
    }
    return false;
}

} // namespace hyc
