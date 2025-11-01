#pragma once

#include "ast.hpp"
#include "diag.hpp"

#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace hyc {

class SemanticAnalyzer {
  public:
    explicit SemanticAnalyzer(Diagnostics& diags);

    bool analyze(Program& program);

  private:
    struct VariableInfo {
        SimpleTypeKind type;
        SourceLocation loc;
    };

    struct FunctionInfo {
        std::vector<SimpleTypeKind> params;
        SimpleTypeKind result = SimpleTypeKind::Int;
        SourceLocation loc;
        bool defined = false;
        FunctionDecl* decl = nullptr;
    };

    class Scope {
      public:
        bool declare(const std::string& name, VariableInfo info);
        VariableInfo* lookup(const std::string& name);

      private:
        std::unordered_map<std::string, VariableInfo> variables_;
    };

    void push_scope();
    void pop_scope();

    VariableInfo* lookup_variable(const std::string& name);
    bool declare_variable(const std::string& name, VariableInfo info);

    FunctionInfo* lookup_function(const std::string& name);
    bool declare_function(const std::string& name, FunctionInfo info);

    bool check_decl(Decl& decl);
    bool check_function(FunctionDecl& func);
    bool check_global_var(GlobalVarDecl& var);

    bool check_statement(Stmt& stmt, SimpleTypeKind expected_return);
    bool check_var_decl(VarDeclStmt& var);
    bool check_return(ReturnStmt& stmt, SimpleTypeKind expected_return);
    bool check_expr_stmt(ExprStmt& stmt);

    std::optional<SimpleTypeKind> check_expr(Expr& expr);

    Diagnostics& diags_;
    std::vector<Scope> scope_stack_;
    std::unordered_map<std::string, FunctionInfo> functions_;
    bool has_main_ = false;
};

} // namespace hyc
