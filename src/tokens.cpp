#include "tokens.hpp"

namespace hydrogenc {

std::string to_string(TokenKind kind) {
    switch (kind) {
    case TokenKind::EndOfFile:
        return "end of file";
    case TokenKind::Identifier:
        return "identifier";
    case TokenKind::Integer:
        return "integer";
    case TokenKind::KeywordVar:
        return "Var";
    case TokenKind::KeywordFunction:
        return "Function";
    case TokenKind::KeywordReturn:
        return "Return";
    case TokenKind::KeywordPrint:
        return "Print";
    case TokenKind::KeywordInt:
        return "Int";
    case TokenKind::LParen:
        return "(";
    case TokenKind::RParen:
        return ")";
    case TokenKind::LBrace:
        return "{";
    case TokenKind::RBrace:
        return "}";
    case TokenKind::Comma:
        return ",";
    case TokenKind::Semicolon:
        return ";";
    case TokenKind::Equal:
        return "=";
    case TokenKind::Unknown:
    default:
        return "unknown";
    }
}

} // namespace hydrogenc
