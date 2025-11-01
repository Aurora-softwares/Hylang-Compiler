#pragma once

#include "ast.hpp"
#include "diag.hpp"
#include "tokens.hpp"

#include <memory>
#include <vector>

namespace hyc {

class Parser {
  public:
    Parser(const std::vector<Token>& tokens, Diagnostics& diags);

    std::unique_ptr<Program> parse_program();

  private:
    const Token& peek(std::size_t offset = 0) const;
    bool is(TokenKind kind, std::size_t offset = 0) const;
    const Token& advance();
    bool match(TokenKind kind);
    const Token& expect(TokenKind kind, const char* message);

    TypeAnnotation parse_type();

    std::unique_ptr<Decl> parse_declaration();
    std::unique_ptr<Decl> parse_var_declaration();
    std::unique_ptr<FunctionDecl> parse_function_declaration();

    Param parse_param();
    std::vector<Param> parse_param_list();

    std::vector<std::unique_ptr<Stmt>> parse_block();
    std::unique_ptr<Stmt> parse_statement();
    std::unique_ptr<Stmt> parse_var_statement();
    std::unique_ptr<Stmt> parse_return_statement();
    std::unique_ptr<Stmt> parse_expression_statement();

    std::unique_ptr<Expr> parse_expression();
    std::unique_ptr<Expr> parse_assignment();
    std::unique_ptr<Expr> parse_primary();

    Diagnostics& diags_;
    const std::vector<Token>& tokens_;
    std::size_t index_ = 0;
};

} // namespace hyc
