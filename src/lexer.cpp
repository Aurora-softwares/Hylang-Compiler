#include "lexer.hpp"

#include <cctype>
#include <stdexcept>

#include "util.hpp"

Lexer::Lexer(const std::string &filename, const std::string &input, DiagnosticsEngine &diag)
    : filename_(filename), input_(input), diag_(diag) {}

Token Lexer::makeToken(TokenKind kind, std::string lexeme, std::size_t line, std::size_t column) {
    return Token{kind, std::move(lexeme), line, column};
}

char Lexer::current() const {
    if (index_ >= input_.size()) {
        return '\0';
    }
    return input_[index_];
}

char Lexer::peekChar(std::size_t offset) const {
    if (index_ + offset >= input_.size()) {
        return '\0';
    }
    return input_[index_ + offset];
}

bool Lexer::eof() const { return index_ >= input_.size(); }

void Lexer::advance() {
    if (eof()) {
        return;
    }
    if (current() == '\n') {
        ++line_;
        column_ = 1;
    } else {
        ++column_;
    }
    ++index_;
}

void Lexer::skipWhitespaceAndComments() {
    while (!eof()) {
        char c = current();
        if (std::isspace(static_cast<unsigned char>(c))) {
            advance();
            continue;
        }
        if (c == '/' && peekChar() == '/') {
            while (!eof() && current() != '\n') {
                advance();
            }
            continue;
        }
        if (c == '/' && peekChar() == '*') {
            advance();
            advance();
            while (!eof()) {
                if (current() == '*' && peekChar() == '/') {
                    advance();
                    advance();
                    break;
                }
                advance();
            }
            continue;
        }
        break;
    }
}

Token Lexer::lexIdentifierOrKeyword() {
    std::size_t start = index_;
    std::size_t startColumn = column_;
    std::size_t startLine = line_;
    while (std::isalnum(static_cast<unsigned char>(current())) || current() == '_') {
        advance();
    }
    std::string text = input_.substr(start, index_ - start);
    std::string lower = toLowerCopy(text);
    if (lower == "var") return makeToken(TokenKind::KeywordVar, text, startLine, startColumn);
    if (lower == "function") return makeToken(TokenKind::KeywordFunction, text, startLine, startColumn);
    if (lower == "return") return makeToken(TokenKind::KeywordReturn, text, startLine, startColumn);
    if (lower == "int") return makeToken(TokenKind::KeywordInt, text, startLine, startColumn);
    if (lower == "print") return makeToken(TokenKind::KeywordPrint, text, startLine, startColumn);
    return makeToken(TokenKind::Identifier, text, startLine, startColumn);
}

Token Lexer::lexNumber() {
    std::size_t start = index_;
    std::size_t startColumn = column_;
    std::size_t startLine = line_;
    while (std::isdigit(static_cast<unsigned char>(current()))) {
        advance();
    }
    std::string text = input_.substr(start, index_ - start);
    return makeToken(TokenKind::Integer, text, startLine, startColumn);
}

Token Lexer::next() {
    if (hasLookahead_) {
        hasLookahead_ = false;
        return lookahead_;
    }
    skipWhitespaceAndComments();
    if (eof()) {
        return makeToken(TokenKind::EndOfFile, "", line_, column_);
    }
    char c = current();
    std::size_t startColumn = column_;
    if (std::isalpha(static_cast<unsigned char>(c)) || c == '_') {
        return lexIdentifierOrKeyword();
    }
    if (std::isdigit(static_cast<unsigned char>(c))) {
        return lexNumber();
    }
    advance();
    switch (c) {
    case '(':
        return makeToken(TokenKind::LParen, "(", line_, startColumn);
    case ')':
        return makeToken(TokenKind::RParen, ")", line_, startColumn);
    case '{':
        return makeToken(TokenKind::LBrace, "{", line_, startColumn);
    case '}':
        return makeToken(TokenKind::RBrace, "}", line_, startColumn);
    case ',':
        return makeToken(TokenKind::Comma, ",", line_, startColumn);
    case ';':
        return makeToken(TokenKind::Semicolon, ";", line_, startColumn);
    case '=':
        return makeToken(TokenKind::Equal, "=", line_, startColumn);
    default:
        diag_.error(line_, startColumn, std::string("unexpected character '") + c + "'");
        return makeToken(TokenKind::EndOfFile, "", line_, startColumn);
    }
}

const Token &Lexer::peek() {
    if (!hasLookahead_) {
        lookahead_ = next();
        hasLookahead_ = true;
    }
    return lookahead_;
}
