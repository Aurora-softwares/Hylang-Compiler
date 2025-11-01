#pragma once

#include <string>
#include <vector>

#include "diag.hpp"
#include "tokens.hpp"

class Lexer {
public:
    Lexer(const std::string &filename, const std::string &input, DiagnosticsEngine &diag);

    Token next();
    const Token &peek();

private:
    Token makeToken(TokenKind kind, std::string lexeme, std::size_t line, std::size_t column);
    Token lexIdentifierOrKeyword();
    Token lexNumber();
    void skipWhitespaceAndComments();

    char current() const;
    char peekChar(std::size_t offset = 1) const;
    bool eof() const;
    void advance();

    std::string filename_;
    const std::string &input_;
    DiagnosticsEngine &diag_;
    std::size_t index_{0};
    std::size_t line_{1};
    std::size_t column_{1};
    Token lookahead_;
    bool hasLookahead_{false};
};
