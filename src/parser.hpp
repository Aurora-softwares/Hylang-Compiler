#pragma once

#include "ast.hpp"
#include "diag.hpp"
#include "lexer.hpp"

#include <memory>
#include <vector>

namespace hydrogenc {

class Parser {
public:
    Parser(const std::vector<Token>& tokens, DiagnosticEngine& diag);

    std::unique_ptr<Program> parse_program();

private:
    const Token& current() const;
    bool check(TokenKind kind) const;
    bool match(TokenKind kind);
    const Token& consume(TokenKind kind, const std::string& message);

    std::unique_ptr<VarDeclStmt> parse_global_var();
    std::unique_ptr<FunctionDefinition> parse_function();
    Type parse_type();

    std::unique_ptr<BlockStmt> parse_block();
    std::unique_ptr<Stmt> parse_statement();
    std::unique_ptr<VarDeclStmt> parse_var_decl(bool is_global);
    std::unique_ptr<Stmt> parse_return_statement();
    std::unique_ptr<Stmt> parse_expr_statement();
    std::unique_ptr<Expr> parse_expression();
    std::unique_ptr<Expr> parse_assignment();
    std::unique_ptr<Expr> parse_call_or_primary();
    std::unique_ptr<Expr> parse_primary();

    DiagnosticEngine& diag_;
    const std::vector<Token>& tokens_;
    std::size_t index_ = 0;
};

} // namespace hydrogenc
