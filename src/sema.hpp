#pragma once

#include "ast.hpp"
#include "diag.hpp"

#include <string>
#include <unordered_map>
#include <vector>

namespace hyc {

class Sema {
  public:
    Sema(Diagnostics &diag, std::string source);

    bool analyze(Program &program);

    struct FunctionInfo {
        std::string name;
        std::size_t paramCount = 0;
        FunctionDecl *decl = nullptr;
        bool isBuiltin = false;
    };

    const std::unordered_map<std::string, FunctionInfo> &functions() const { return m_functions; }

  private:
    struct Scope {
        std::unordered_map<std::string, SourceLocation> variables;
    };

    void pushScope();
    void popScope();
    bool declareVariable(const std::string &name, const SourceLocation &loc);
    bool variableExists(const std::string &name) const;

    bool checkDeclaration(Decl *decl);
    bool checkFunction(FunctionDecl *decl);
    bool checkBlock(BlockStmt *block);
    bool checkStatement(Stmt *stmt);
    bool checkVarDecl(VarDeclStmt *stmt);
    bool checkReturn(ReturnStmt *stmt);
    bool checkExpr(Expr *expr);

    std::string lineText(unsigned line) const;

    Diagnostics &m_diag;
    std::string m_source;
    std::vector<std::string> m_lines;
    std::vector<Scope> m_scopes;
    std::unordered_map<std::string, FunctionInfo> m_functions;
    std::unordered_map<std::string, SourceLocation> m_globalVariables;
    bool m_hasMain = false;
};

} // namespace hyc
