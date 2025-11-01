#pragma once

#include <string>

namespace hyc {

enum class TokenKind {
    EndOfFile,
    Identifier,
    Integer,

    // Keywords
    KwVar,
    KwFunction,
    KwReturn,
    KwPrint,
    KwInt,

    // punctuation
    LParen,
    RParen,
    LBrace,
    RBrace,
    Comma,
    Semicolon,
    Equal,
};

struct SourceLocation {
    std::string file;
    std::size_t line = 1;
    std::size_t column = 1;
};

struct Token {
    TokenKind kind;
    std::string text;
    SourceLocation location;
};

std::string to_string(TokenKind kind);

} // namespace hyc
