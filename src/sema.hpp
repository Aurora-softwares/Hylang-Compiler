#pragma once

#include "ast.hpp"
#include "diag.hpp"

#include <string>
#include <unordered_map>
#include <vector>

namespace hydrogenc {

struct FunctionInfo {
    std::string name;
    std::vector<Param> parameters;
    Type return_type;
    bool is_builtin = false;
    SourceLocation location;
};

struct VariableInfo {
    std::string name;
    Type type;
    SourceLocation location;
};

class Sema {
public:
    Sema(DiagnosticEngine& diag);

    bool analyze(Program& program);

private:
    void declare_builtin_functions();
    bool declare_globals(Program& program);
    bool declare_functions(Program& program);
    bool analyze_global(VarDeclStmt& decl);
    bool analyze_function(FunctionDefinition& fn);
    bool analyze_block(BlockStmt& block, std::vector<VariableInfo>& scope);
    bool analyze_statement(Stmt& stmt, std::vector<VariableInfo>& scope);
    bool analyze_expression(Expr& expr, std::vector<VariableInfo>& scope, Type& out_type);
    VariableInfo* resolve_variable(const std::string& name, std::vector<VariableInfo>& scope);
    FunctionInfo* resolve_function(const std::string& name);

    DiagnosticEngine& diag_;
    std::unordered_map<std::string, VariableInfo> globals_;
    std::unordered_map<std::string, FunctionInfo> functions_;
};

} // namespace hydrogenc
