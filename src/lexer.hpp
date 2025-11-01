#pragma once

#include "diag.hpp"
#include "tokens.hpp"

#include <string>
#include <vector>

namespace hyc {

class Lexer {
  public:
    Lexer(const std::string& filename, const std::string& source,
          Diagnostics& diags);

    const std::vector<Token>& tokens() const { return tokens_; }

    void lex();

  private:
    char peek(std::size_t offset = 0) const;
    char get();
    bool match(char expected);

    void skip_whitespace();
    void skip_comment();

    void lex_identifier_or_keyword();
    void lex_number();
    void lex_punctuation(char c, TokenKind kind);

    SourceLocation current_location() const;

    void push_token(TokenKind kind, const std::string& text,
                    const SourceLocation& loc);

    const std::string& filename_;
    const std::string& source_;
    Diagnostics& diags_;
    std::size_t index_ = 0;
    std::size_t line_ = 1;
    std::size_t column_ = 1;
    std::vector<Token> tokens_;
};

} // namespace hyc
