#include "lexer.hpp"

#include "util.hpp"

#include <cctype>
#include <exception>

namespace hydrogenc {

Lexer::Lexer(std::string source, DiagnosticEngine& diag)
    : source_(std::move(source)), diag_(diag) {}

std::vector<Token> Lexer::lex() {
    while (index_ < source_.size()) {
        skip_whitespace_and_comments();
        if (index_ >= source_.size()) {
            break;
        }

        char c = peek();
        if (std::isalpha(static_cast<unsigned char>(c)) || c == '_') {
            lex_identifier();
        } else if (std::isdigit(static_cast<unsigned char>(c))) {
            lex_number();
        } else {
            Token token;
            token.location = {line_, column_};
            switch (c) {
            case '(':
                advance();
                token.kind = TokenKind::LParen;
                token.lexeme = "(";
                break;
            case ')':
                advance();
                token.kind = TokenKind::RParen;
                token.lexeme = ")";
                break;
            case '{':
                advance();
                token.kind = TokenKind::LBrace;
                token.lexeme = "{";
                break;
            case '}':
                advance();
                token.kind = TokenKind::RBrace;
                token.lexeme = "}";
                break;
            case ',':
                advance();
                token.kind = TokenKind::Comma;
                token.lexeme = ",";
                break;
            case ';':
                advance();
                token.kind = TokenKind::Semicolon;
                token.lexeme = ";";
                break;
            case '=':
                advance();
                token.kind = TokenKind::Equal;
                token.lexeme = "=";
                break;
            default:
                diag_.report({DiagnosticLevel::Error, token.location, std::string("unexpected character '") + c + "'", 1});
                advance();
                continue;
            }
            add_token(std::move(token));
        }
    }

    Token eof;
    eof.kind = TokenKind::EndOfFile;
    eof.location = {line_, column_};
    tokens_.push_back(std::move(eof));
    return tokens_;
}

char Lexer::peek() const {
    if (index_ >= source_.size()) {
        return '\0';
    }
    return source_[index_];
}

char Lexer::peek_next() const {
    if (index_ + 1 >= source_.size()) {
        return '\0';
    }
    return source_[index_ + 1];
}

char Lexer::advance() {
    char c = source_[index_++];
    if (c == '\n') {
        ++line_;
        column_ = 1;
    } else {
        ++column_;
    }
    return c;
}

void Lexer::skip_whitespace_and_comments() {
    while (index_ < source_.size()) {
        char c = peek();
        if (c == ' ' || c == '\r' || c == '\t' || c == '\n') {
            advance();
            continue;
        }
        if (c == '/' && peek_next() == '/') {
            while (peek() != '\n' && index_ < source_.size()) {
                advance();
            }
            continue;
        }
        if (c == '/' && peek_next() == '*') {
            advance();
            advance();
            while (index_ < source_.size()) {
                if (peek() == '*' && peek_next() == '/') {
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

void Lexer::lex_identifier() {
    std::size_t start_index = index_;
    std::size_t start_column = column_;
    while (std::isalnum(static_cast<unsigned char>(peek())) || peek() == '_') {
        advance();
    }
    std::string text = source_.substr(start_index, index_ - start_index);
    std::string lowered = to_lower_copy(text);

    Token token;
    token.location = {line_, start_column};
    token.lexeme = text;

    if (lowered == "var") {
        token.kind = TokenKind::KeywordVar;
    } else if (lowered == "function") {
        token.kind = TokenKind::KeywordFunction;
    } else if (lowered == "return") {
        token.kind = TokenKind::KeywordReturn;
    } else if (lowered == "print") {
        token.kind = TokenKind::KeywordPrint;
    } else if (lowered == "int") {
        token.kind = TokenKind::KeywordInt;
    } else {
        token.kind = TokenKind::Identifier;
    }

    add_token(std::move(token));
}

void Lexer::lex_number() {
    std::size_t start_index = index_;
    std::size_t start_column = column_;
    while (std::isdigit(static_cast<unsigned char>(peek()))) {
        advance();
    }
    std::string text = source_.substr(start_index, index_ - start_index);
    Token token;
    token.location = {line_, start_column};
    token.kind = TokenKind::Integer;
    token.lexeme = text;
    try {
        token.int_value = static_cast<std::int32_t>(std::stoll(text));
    } catch (const std::exception&) {
        diag_.report({DiagnosticLevel::Error, token.location, "integer literal out of range", text.size()});
        token.int_value = 0;
    }
    add_token(std::move(token));
}

void Lexer::add_token(Token token) {
    tokens_.push_back(std::move(token));
}

} // namespace hydrogenc
