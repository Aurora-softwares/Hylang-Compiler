#pragma once

#include <string>

enum class TokenKind {
    EndOfFile,
    Identifier,
    Integer,
    KeywordVar,
    KeywordFunction,
    KeywordReturn,
    KeywordInt,
    KeywordPrint,
    LParen,
    RParen,
    LBrace,
    RBrace,
    Comma,
    Semicolon,
    Equal
};

struct Token {
    TokenKind kind{TokenKind::EndOfFile};
    std::string lexeme;
    std::size_t line{0};
    std::size_t column{0};
};

inline bool isKeyword(TokenKind kind) {
    switch (kind) {
    case TokenKind::KeywordVar:
    case TokenKind::KeywordFunction:
    case TokenKind::KeywordReturn:
    case TokenKind::KeywordInt:
    case TokenKind::KeywordPrint:
        return true;
    default:
        return false;
    }
}

inline const char *tokenKindName(TokenKind kind) {
    switch (kind) {
    case TokenKind::EndOfFile: return "<eof>";
    case TokenKind::Identifier: return "identifier";
    case TokenKind::Integer: return "integer";
    case TokenKind::KeywordVar: return "Var";
    case TokenKind::KeywordFunction: return "Function";
    case TokenKind::KeywordReturn: return "Return";
    case TokenKind::KeywordInt: return "Int";
    case TokenKind::KeywordPrint: return "Print";
    case TokenKind::LParen: return "(";
    case TokenKind::RParen: return ")";
    case TokenKind::LBrace: return "{";
    case TokenKind::RBrace: return "}";
    case TokenKind::Comma: return ",";
    case TokenKind::Semicolon: return ";";
    case TokenKind::Equal: return "=";
    }
    return "?";
}
