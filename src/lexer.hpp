#pragma once

#include "diag.hpp"
#include "tokens.hpp"

#include <string>
#include <vector>

namespace hyc {

class Lexer {
  public:
    Lexer(std::string source, std::string filename, Diagnostics &diag);

    std::vector<Token> lex();

  private:
    char peek(std::size_t offset = 0) const;
    char advance();
    bool match(char expected);
    void skipWhitespaceAndComments();

    Token makeToken(TokenKind kind, std::string lexeme, unsigned line, unsigned column);
    Token lexIdentifierOrKeyword();
    Token lexNumber();

    std::string m_source;
    std::string m_filename;
    Diagnostics &m_diag;
    std::size_t m_index = 0;
    unsigned m_line = 1;
    unsigned m_column = 1;
};

} // namespace hyc
