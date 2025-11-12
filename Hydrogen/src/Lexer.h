#pragma once

#include <string>
#include <vector>

#include "Error.h"
#include "Token.h"
#include "Utils.h"

namespace hy {

class Lexer {
public:
    Lexer(std::string source, DiagnosticEngine &diag);

    std::vector<Token> tokenize();

private:
    Token lexToken();
    Token lexIdentifierOrKeyword();
    Token lexNumber();
    void skipWhitespaceAndComments();
    bool match(char expected);
    char peek(std::size_t offset = 0) const;
    char advance();
    bool isAtEnd() const;

    std::string source_;
    std::size_t index_{0};
    std::size_t line_{1};
    std::size_t column_{1};
    DiagnosticEngine &diag_;
};

} // namespace hy
