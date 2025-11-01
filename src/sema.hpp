#pragma once

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include "ast.hpp"
#include "diag.hpp"

struct FunctionSignature {
    std::vector<SimpleType> parameters;
};

class Sema {
public:
    explicit Sema(DiagnosticsEngine &diag);

    bool analyze(Program &program);

    const std::unordered_map<std::string, FunctionSignature> &functions() const { return functions_; }
    const std::unordered_map<std::string, VarDecl *> &globals() const { return globals_; }

private:
    void declareBuiltins();
    void gatherFunctions(Program &program);
    void analyzeTopLevel(TopLevelDecl &decl);
    void analyzeFunction(FunctionDecl &func);
    void analyzeStatement(Statement &stmt);
    void analyzeVarDecl(VarDecl &decl);
    void analyzeReturn(Statement::ReturnStmt &stmt, const SourceLocation &loc);
    void analyzeExpr(Expr &expr);

    void enterScope();
    void exitScope();
    bool declareVariable(const std::string &name, VarDecl *decl, const SourceLocation &loc);
    bool isVariableDefined(const std::string &name) const;

    DiagnosticsEngine &diag_;
    Program *program_{nullptr};
    std::unordered_map<std::string, FunctionSignature> functions_;
    std::unordered_map<std::string, VarDecl *> globals_;
    std::vector<std::unordered_map<std::string, VarDecl *>> scopes_;
    FunctionDecl *currentFunction_{nullptr};
};
