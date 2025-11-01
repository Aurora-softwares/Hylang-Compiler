#pragma once

#include <memory>
#include <optional>
#include <vector>

#include "ast.hpp"
#include "lexer.hpp"

class Parser {
public:
    Parser(Lexer &lexer, DiagnosticsEngine &diag);

    std::unique_ptr<Program> parseProgram();

private:
    const Token &peek();
    Token consume();
    bool match(TokenKind kind);
    Token expect(TokenKind kind, const std::string &message);

    std::unique_ptr<TopLevelDecl> parseDeclaration();
    std::unique_ptr<TopLevelDecl> parseVarDecl();
    std::unique_ptr<TopLevelDecl> parseFunctionDecl();

    std::unique_ptr<FunctionDecl> parseFunctionBody(std::string name, SourceLocation loc);
    Parameter parseParameter();
    SimpleType parseType();
    std::unique_ptr<Statement> parseStatement();
    std::unique_ptr<Statement> parseVarDeclStmt();
    std::unique_ptr<Statement> parseReturnStmt();
    std::unique_ptr<Statement> parseExprStmt();

    std::unique_ptr<Expr> parseExpression();
    std::unique_ptr<Expr> parseAssignment();
    std::unique_ptr<Expr> parsePrimary();
    std::unique_ptr<Expr> parseCallOrPrimary();

    Lexer &lexer_;
    DiagnosticsEngine &diag_;
};
