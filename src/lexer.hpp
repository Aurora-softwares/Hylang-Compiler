#pragma once

#include "diag.hpp"
#include "tokens.hpp"

#include <string>
#include <vector>

namespace hydrogenc {

class Lexer {
public:
    Lexer(std::string source, DiagnosticEngine& diag);

    std::vector<Token> lex();

private:
    char peek() const;
    char peek_next() const;
    char advance();
    void skip_whitespace_and_comments();
    void lex_identifier();
    void lex_number();
    void add_token(Token token);

    std::string source_;
    DiagnosticEngine& diag_;
    std::vector<Token> tokens_;
    std::size_t index_ = 0;
    std::size_t line_ = 1;
    std::size_t column_ = 1;
};

} // namespace hydrogenc
