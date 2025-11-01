#include "lexer.hpp"

#include "util.hpp"

#include <cctype>

namespace hyc {

Lexer::Lexer(const std::string& filename, const std::string& source,
             Diagnostics& diags)
    : filename_(filename), source_(source), diags_(diags) {}

void Lexer::lex() {
    while (index_ < source_.size()) {
        skip_whitespace();
        if (index_ >= source_.size()) {
            break;
        }

        char c = peek();
        if (std::isalpha(static_cast<unsigned char>(c)) || c == '_') {
            lex_identifier_or_keyword();
            continue;
        }
        if (std::isdigit(static_cast<unsigned char>(c))) {
            lex_number();
            continue;
        }

        SourceLocation loc = current_location();
        switch (c) {
        case '(':
            lex_punctuation(c, TokenKind::LParen);
            break;
        case ')':
            lex_punctuation(c, TokenKind::RParen);
            break;
        case '{':
            lex_punctuation(c, TokenKind::LBrace);
            break;
        case '}':
            lex_punctuation(c, TokenKind::RBrace);
            break;
        case ',':
            lex_punctuation(c, TokenKind::Comma);
            break;
        case ';':
            lex_punctuation(c, TokenKind::Semicolon);
            break;
        case '=':
            lex_punctuation(c, TokenKind::Equal);
            break;
        case '/':
            if (peek(1) == '/' || peek(1) == '*') {
                skip_comment();
                break;
            }
            [[fallthrough]];
        default:
            diags_.error(loc, std::string("unexpected character '") + c + "'");
            ++index_;
            ++column_;
            break;
        }
    }

    push_token(TokenKind::EndOfFile, "", current_location());
}

char Lexer::peek(std::size_t offset) const {
    if (index_ + offset >= source_.size()) {
        return '\0';
    }
    return source_[index_ + offset];
}

char Lexer::get() {
    char c = peek();
    if (c == '\n') {
        ++line_;
        column_ = 1;
    } else {
        ++column_;
    }
    ++index_;
    return c;
}

bool Lexer::match(char expected) {
    if (peek() != expected) {
        return false;
    }
    get();
    return true;
}

void Lexer::skip_whitespace() {
    while (index_ < source_.size()) {
        char c = peek();
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            get();
            continue;
        }
        if (c == '/' && (peek(1) == '/' || peek(1) == '*')) {
            skip_comment();
            continue;
        }
        break;
    }
}

void Lexer::skip_comment() {
    if (match('/') && match('/')) {
        while (index_ < source_.size() && peek() != '\n') {
            get();
        }
    } else if (source_[index_] == '/' && peek(1) == '*') {
        // Consume '/*'
        get();
        get();
        while (index_ < source_.size()) {
            if (peek() == '*' && peek(1) == '/') {
                get();
                get();
                break;
            }
            get();
        }
    }
}

void Lexer::lex_identifier_or_keyword() {
    SourceLocation loc = current_location();
    std::string text;
    while (index_ < source_.size()) {
        char c = peek();
        if (std::isalnum(static_cast<unsigned char>(c)) || c == '_') {
            text.push_back(get());
        } else {
            break;
        }
    }
    std::string lower = to_lower_copy(text);
    TokenKind kind = TokenKind::Identifier;
    if (lower == "var") {
        kind = TokenKind::KwVar;
    } else if (lower == "function") {
        kind = TokenKind::KwFunction;
    } else if (lower == "return") {
        kind = TokenKind::KwReturn;
    } else if (lower == "print") {
        kind = TokenKind::KwPrint;
    } else if (lower == "int") {
        kind = TokenKind::KwInt;
    }
    push_token(kind, text, loc);
}

void Lexer::lex_number() {
    SourceLocation loc = current_location();
    std::string text;
    while (index_ < source_.size() &&
           std::isdigit(static_cast<unsigned char>(peek()))) {
        text.push_back(get());
    }
    push_token(TokenKind::Integer, text, loc);
}

void Lexer::lex_punctuation(char c, TokenKind kind) {
    SourceLocation loc = current_location();
    get();
    push_token(kind, std::string(1, c), loc);
}

SourceLocation Lexer::current_location() const {
    return SourceLocation{filename_, line_, column_};
}

void Lexer::push_token(TokenKind kind, const std::string& text,
                       const SourceLocation& loc) {
    tokens_.push_back(Token{kind, text, loc});
}

} // namespace hyc
