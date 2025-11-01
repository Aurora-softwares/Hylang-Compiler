#include "tokens.hpp"

namespace hyc {

std::string to_string(TokenKind kind) {
    switch (kind) {
    case TokenKind::EndOfFile:
        return "end of file";
    case TokenKind::Identifier:
        return "identifier";
    case TokenKind::Integer:
        return "integer literal";
    case TokenKind::KwVar:
        return "'Var'";
    case TokenKind::KwFunction:
        return "'Function'";
    case TokenKind::KwReturn:
        return "'Return'";
    case TokenKind::KwPrint:
        return "'Print'";
    case TokenKind::KwInt:
        return "'Int'";
    case TokenKind::LParen:
        return "'('";
    case TokenKind::RParen:
        return "')'";
    case TokenKind::LBrace:
        return "'{'";
    case TokenKind::RBrace:
        return "'}'";
    case TokenKind::Comma:
        return "','";
    case TokenKind::Semicolon:
        return "';'";
    case TokenKind::Equal:
        return "'='";
    }
    return "<unknown>";
}

} // namespace hyc
