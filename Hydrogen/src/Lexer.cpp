#include "Lexer.h"

#include <unordered_map>

namespace hy {

Lexer::Lexer(std::string source, DiagnosticEngine &diag)
    : source_(std::move(source)), diag_(diag) {}

std::vector<Token> Lexer::tokenize() {
    std::vector<Token> tokens;
    while (!isAtEnd()) {
        skipWhitespaceAndComments();
        if (isAtEnd()) {
            break;
        }
        Token token = lexToken();
        tokens.push_back(std::move(token));
    }
    Token eof;
    eof.kind = TokenKind::EndOfFile;
    eof.location = {line_, column_};
    tokens.push_back(std::move(eof));
    return tokens;
}

Token Lexer::lexToken() {
    char c = advance();
    SourceLocation loc{line_, column_ - 1};

    switch (c) {
    case '{':
        return {TokenKind::LBrace, "{", loc};
    case '}':
        return {TokenKind::RBrace, "}", loc};
    case '(':
        return {TokenKind::LParen, "(", loc};
    case ')':
        return {TokenKind::RParen, ")", loc};
    case ';':
        return {TokenKind::Semicolon, ";", loc};
    case '.':
        return {TokenKind::Dot, ".", loc};
    case '=':
        return {TokenKind::Equal, "=", loc};
    case ':':
        if (match(':')) {
            return {TokenKind::ColonColon, "::", loc};
        }
        break;
    case '-':
        if (match('>')) {
            return {TokenKind::Arrow, "->", loc};
        }
        break;
    default:
        if (isIdentifierStart(c)) {
            index_--;
            column_--;
            return lexIdentifierOrKeyword();
        }
        if (isDigit(c)) {
            index_--;
            column_--;
            return lexNumber();
        }
        break;
    }

    diag_.error(loc, std::string("unexpected character '") + c + "'");
    return {TokenKind::Unknown, std::string(1, c), loc};
}

Token Lexer::lexIdentifierOrKeyword() {
    SourceLocation loc{line_, column_};
    std::size_t start = index_;
    advance();
    while (!isAtEnd() && isIdentifierPart(peek())) {
        advance();
    }
    std::string text = source_.substr(start, index_ - start);
    static const std::unordered_map<std::string, TokenKind> keywords{
        {"namespace", TokenKind::Namespace},
        {"fn", TokenKind::Fn},
        {"return", TokenKind::Return},
        {"int", TokenKind::Int},
    };
    auto it = keywords.find(text);
    if (it != keywords.end()) {
        return {it->second, text, loc};
    }
    return {TokenKind::Identifier, text, loc};
}

Token Lexer::lexNumber() {
    SourceLocation loc{line_, column_};
    std::size_t start = index_;
    advance();
    while (!isAtEnd() && isDigit(peek())) {
        advance();
    }
    std::string text = source_.substr(start, index_ - start);
    return {TokenKind::Integer, text, loc};
}

void Lexer::skipWhitespaceAndComments() {
    while (!isAtEnd()) {
        char c = peek();
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            advance();
            continue;
        }
        if (c == '/' && peek(1) == '/') {
            while (!isAtEnd() && peek() != '\n') {
                advance();
            }
            continue;
        }
        break;
    }
}

bool Lexer::match(char expected) {
    if (isAtEnd() || source_[index_] != expected) {
        return false;
    }
    advance();
    return true;
}

char Lexer::peek(std::size_t offset) const {
    if (index_ + offset >= source_.size()) {
        return '\0';
    }
    return source_[index_ + offset];
}

char Lexer::advance() {
    char c = source_[index_++];
    if (c == '\n') {
        line_++;
        column_ = 1;
    } else {
        column_++;
    }
    return c;
}

bool Lexer::isAtEnd() const {
    return index_ >= source_.size();
}

} // namespace hy
