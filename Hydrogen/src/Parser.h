#pragma once

#include <memory>
#include <vector>

#include "AST.h"
#include "Error.h"
#include "Token.h"

namespace hy {

class Parser {
public:
    Parser(const std::vector<Token> &tokens, DiagnosticEngine &diag);

    std::unique_ptr<ast::Module> parse();

private:
    const Token &peek() const;
    const Token &previous() const;
    bool match(TokenKind kind);
    bool expect(TokenKind kind, const std::string &message);
    bool isAtEnd() const;

    std::unique_ptr<ast::NamespaceDecl> parseNamespace();
    std::unique_ptr<ast::FuncDecl> parseFunction();
    std::unique_ptr<ast::Block> parseBlock();
    std::unique_ptr<ast::ReturnStmt> parseReturn();
    std::unique_ptr<ast::IntegerLiteral> parseIntegerLiteral();

    const std::vector<Token> &tokens_;
    std::size_t current_{0};
    DiagnosticEngine &diag_;
};

} // namespace hy
