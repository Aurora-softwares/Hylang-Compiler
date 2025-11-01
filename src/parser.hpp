#pragma once

#include "ast.hpp"
#include "diag.hpp"
#include "tokens.hpp"

#include <memory>
#include <string>
#include <vector>

namespace hyc {

class Parser {
  public:
    Parser(const std::vector<Token> &tokens, std::string source, Diagnostics &diag);

    Program parseProgram();

  private:
    const Token &peek(std::size_t offset = 0) const;
    bool check(TokenKind kind, std::size_t offset = 0) const;
    bool match(TokenKind kind);
    const Token &consume(TokenKind kind, const std::string &message);

    void synchronize();
    std::string lineText(unsigned line) const;

    std::unique_ptr<Decl> parseDeclaration();
    std::unique_ptr<VarDecl> parseGlobalVar();
    std::unique_ptr<FunctionDecl> parseFunction();

    std::unique_ptr<VarDeclStmt> parseVarDeclStmt(bool isGlobal);
    std::unique_ptr<Stmt> parseStatement();
    std::unique_ptr<BlockStmt> parseBlock();
    std::unique_ptr<Stmt> parseReturnStmt();
    std::unique_ptr<Stmt> parseExprStmt();

    std::unique_ptr<Expr> parseExpression();
    std::unique_ptr<Expr> parseAssignment();
    std::unique_ptr<Expr> parseCall();
    std::unique_ptr<Expr> parsePrimary();

    Type parseType();

    const std::vector<Token> &m_tokens;
    std::string m_source;
    std::vector<std::string> m_lines;
    Diagnostics &m_diag;
    std::size_t m_index = 0;
};

} // namespace hyc
