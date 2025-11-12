#pragma once

#include <string>

#include "Error.h"

namespace hy {

enum class TokenKind {
    EndOfFile,
    Identifier,
    Integer,
    Namespace,
    Fn,
    Return,
    Int,
    LBrace,
    RBrace,
    LParen,
    RParen,
    Arrow,
    Semicolon,
    Dot,
    ColonColon,
    Equal,
    Unknown,
};

struct Token {
    TokenKind kind{TokenKind::Unknown};
    std::string lexeme;
    SourceLocation location;
};

inline std::string tokenKindToString(TokenKind kind) {
    switch (kind) {
    case TokenKind::EndOfFile:
        return "eof";
    case TokenKind::Identifier:
        return "identifier";
    case TokenKind::Integer:
        return "integer";
    case TokenKind::Namespace:
        return "namespace";
    case TokenKind::Fn:
        return "fn";
    case TokenKind::Return:
        return "return";
    case TokenKind::Int:
        return "int";
    case TokenKind::LBrace:
        return "{";
    case TokenKind::RBrace:
        return "}";
    case TokenKind::LParen:
        return "(";
    case TokenKind::RParen:
        return ")";
    case TokenKind::Arrow:
        return "->";
    case TokenKind::Semicolon:
        return ";";
    case TokenKind::Dot:
        return ".";
    case TokenKind::ColonColon:
        return "::";
    case TokenKind::Equal:
        return "=";
    case TokenKind::Unknown:
    default:
        return "unknown";
    }
}

} // namespace hy
