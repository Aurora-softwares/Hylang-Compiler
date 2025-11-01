#include "lexer.hpp"

#include <cctype>

namespace hyc {

static bool isIdentifierStart(char c) {
    return std::isalpha(static_cast<unsigned char>(c)) || c == '_';
}

static bool isIdentifierChar(char c) {
    return std::isalnum(static_cast<unsigned char>(c)) || c == '_';
}

Lexer::Lexer(std::string source, std::string filename, Diagnostics &diag)
    : m_source(std::move(source)), m_filename(std::move(filename)), m_diag(diag) {}

char Lexer::peek(std::size_t offset) const {
    if (m_index + offset >= m_source.size()) {
        return '\0';
    }
    return m_source[m_index + offset];
}

char Lexer::advance() {
    if (m_index >= m_source.size()) {
        return '\0';
    }
    char c = m_source[m_index++];
    if (c == '\n') {
        ++m_line;
        m_column = 1;
    } else {
        ++m_column;
    }
    return c;
}

bool Lexer::match(char expected) {
    if (peek() == expected) {
        advance();
        return true;
    }
    return false;
}

void Lexer::skipWhitespaceAndComments() {
    while (true) {
        char c = peek();
        if (c == '\0') {
            return;
        }
        if (std::isspace(static_cast<unsigned char>(c))) {
            advance();
            continue;
        }
        if (c == '/' && peek(1) == '/') {
            while (peek() != '\0' && peek() != '\n') {
                advance();
            }
            continue;
        }
        if (c == '/' && peek(1) == '*') {
            advance();
            advance();
            while (peek() != '\0' && !(peek() == '*' && peek(1) == '/')) {
                advance();
            }
            if (peek() == '*' && peek(1) == '/') {
                advance();
                advance();
            }
            continue;
        }
        return;
    }
}

Token Lexer::makeToken(TokenKind kind, std::string lexeme, unsigned line, unsigned column) {
    Token token;
    token.kind = kind;
    token.lexeme = std::move(lexeme);
    token.location.file = m_filename;
    token.location.line = line;
    token.location.column = column;
    return token;
}

Token Lexer::lexIdentifierOrKeyword() {
    unsigned startLine = m_line;
    unsigned startColumn = m_column;
    std::size_t start = m_index;
    while (isIdentifierChar(peek())) {
        advance();
    }
    std::string text = m_source.substr(start, m_index - start);
    std::string lowered;
    lowered.reserve(text.size());
    for (char ch : text) {
        lowered.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(ch))));
    }
    if (lowered == "var") {
        return makeToken(TokenKind::KwVar, text, startLine, startColumn);
    }
    if (lowered == "function") {
        return makeToken(TokenKind::KwFunction, text, startLine, startColumn);
    }
    if (lowered == "return") {
        return makeToken(TokenKind::KwReturn, text, startLine, startColumn);
    }
    if (lowered == "print") {
        return makeToken(TokenKind::KwPrint, text, startLine, startColumn);
    }
    if (lowered == "int") {
        return makeToken(TokenKind::KwInt, text, startLine, startColumn);
    }
    if (lowered == "if" || lowered == "else" || lowered == "while") {
        return makeToken(TokenKind::Unknown, text, startLine, startColumn);
    }
    return makeToken(TokenKind::Identifier, text, startLine, startColumn);
}

Token Lexer::lexNumber() {
    unsigned startLine = m_line;
    unsigned startColumn = m_column;
    std::size_t start = m_index;
    while (std::isdigit(static_cast<unsigned char>(peek()))) {
        advance();
    }
    std::string text = m_source.substr(start, m_index - start);
    return makeToken(TokenKind::Integer, text, startLine, startColumn);
}

std::vector<Token> Lexer::lex() {
    std::vector<Token> tokens;
    while (true) {
        skipWhitespaceAndComments();
        unsigned startLine = m_line;
        unsigned startColumn = m_column;
        char c = peek();
        if (c == '\0') {
            tokens.push_back(makeToken(TokenKind::EndOfFile, "", startLine, startColumn));
            break;
        }
        if (isIdentifierStart(c)) {
            tokens.push_back(lexIdentifierOrKeyword());
            continue;
        }
        if (std::isdigit(static_cast<unsigned char>(c))) {
            tokens.push_back(lexNumber());
            continue;
        }
        advance();
        switch (c) {
        case '(':
            tokens.push_back(makeToken(TokenKind::LParen, "(", startLine, startColumn));
            break;
        case ')':
            tokens.push_back(makeToken(TokenKind::RParen, ")", startLine, startColumn));
            break;
        case '{':
            tokens.push_back(makeToken(TokenKind::LBrace, "{", startLine, startColumn));
            break;
        case '}':
            tokens.push_back(makeToken(TokenKind::RBrace, "}", startLine, startColumn));
            break;
        case ',':
            tokens.push_back(makeToken(TokenKind::Comma, ",", startLine, startColumn));
            break;
        case ';':
            tokens.push_back(makeToken(TokenKind::Semicolon, ";", startLine, startColumn));
            break;
        case '=':
            tokens.push_back(makeToken(TokenKind::Equal, "=", startLine, startColumn));
            break;
        default: {
            std::string lineText;
            std::size_t lineStart = m_source.rfind('\n', m_index - 1);
            std::size_t lineEnd = m_source.find('\n', m_index - 1);
            if (lineStart == std::string::npos) {
                lineStart = 0;
            } else {
                lineStart += 1;
            }
            if (lineEnd == std::string::npos) {
                lineEnd = m_source.size();
            }
            lineText = m_source.substr(lineStart, lineEnd - lineStart);
            m_diag.error({m_filename, startLine, startColumn}, lineText, startColumn - 1, 1, "unexpected character");
            tokens.push_back(makeToken(TokenKind::Unknown, std::string(1, c), startLine, startColumn));
            break;
        }
        }
    }
    return tokens;
}

} // namespace hyc
