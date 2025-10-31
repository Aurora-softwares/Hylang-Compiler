#pragma once

#include <cstdint>
#include <string>

namespace hydrogenc {

struct SourceLocation {
    std::size_t line = 1;
    std::size_t column = 1;
};

enum class TokenKind {
    EndOfFile,
    Identifier,
    Integer,
    KeywordVar,
    KeywordFunction,
    KeywordReturn,
    KeywordPrint,
    KeywordInt,
    LParen,
    RParen,
    LBrace,
    RBrace,
    Comma,
    Semicolon,
    Equal,
    Unknown
};

struct Token {
    TokenKind kind = TokenKind::Unknown;
    std::string lexeme;
    SourceLocation location;
    std::int32_t int_value = 0;
};

std::string to_string(TokenKind kind);

} // namespace hydrogenc
