#pragma once

#include <string>

namespace hyc {

enum class TokenKind {
    EndOfFile,
    Identifier,
    Integer,

    KwVar,
    KwFunction,
    KwReturn,
    KwPrint,
    KwInt,

    LParen,
    RParen,
    LBrace,
    RBrace,
    Comma,
    Semicolon,
    Equal,

    Unknown,
};

struct SourceLocation {
    std::string file;
    unsigned line = 1;
    unsigned column = 1;
};

struct Token {
    TokenKind kind = TokenKind::Unknown;
    std::string lexeme;
    SourceLocation location;
};

std::string tokenKindToString(TokenKind kind);

} // namespace hyc
