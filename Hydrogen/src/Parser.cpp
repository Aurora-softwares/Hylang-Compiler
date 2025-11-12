#include "Parser.h"

#include <cstdlib>

namespace hy {

Parser::Parser(const std::vector<Token> &tokens, DiagnosticEngine &diag)
    : tokens_(tokens), diag_(diag) {}

std::unique_ptr<ast::Module> Parser::parse() {
    auto module = std::make_unique<ast::Module>();
    module->ns = parseNamespace();
    if (!module->ns || diag_.hasError()) {
        return nullptr;
    }
    if (!isAtEnd()) {
        diag_.error(peek().location, "unexpected tokens after namespace");
        return nullptr;
    }
    return module;
}

const Token &Parser::peek() const {
    return tokens_[current_];
}

const Token &Parser::previous() const {
    return tokens_[current_ - 1];
}

bool Parser::match(TokenKind kind) {
    if (peek().kind == kind) {
        current_++;
        return true;
    }
    return false;
}

bool Parser::expect(TokenKind kind, const std::string &message) {
    if (match(kind)) {
        return true;
    }
    diag_.error(peek().location, message);
    return false;
}

bool Parser::isAtEnd() const {
    return peek().kind == TokenKind::EndOfFile;
}

std::unique_ptr<ast::NamespaceDecl> Parser::parseNamespace() {
    if (!expect(TokenKind::Namespace, "expected 'namespace'")) {
        return nullptr;
    }
    if (!expect(TokenKind::Identifier, "expected namespace identifier")) {
        return nullptr;
    }
    auto ns = std::make_unique<ast::NamespaceDecl>();
    ns->name = previous().lexeme;
    if (!expect(TokenKind::LBrace, "expected '{' to start namespace")) {
        return nullptr;
    }
    while (!match(TokenKind::RBrace)) {
        if (peek().kind == TokenKind::EndOfFile) {
            diag_.error(peek().location, "unexpected end of file in namespace");
            return nullptr;
        }
        auto fn = parseFunction();
        if (!fn) {
            return nullptr;
        }
        ns->functions.push_back(std::move(fn));
    }
    return ns;
}

std::unique_ptr<ast::FuncDecl> Parser::parseFunction() {
    if (!expect(TokenKind::Fn, "expected 'fn'")) {
        return nullptr;
    }
    if (!expect(TokenKind::Identifier, "expected function name")) {
        return nullptr;
    }
    auto fn = std::make_unique<ast::FuncDecl>();
    fn->name = previous().lexeme;
    if (!expect(TokenKind::LParen, "expected '(' after function name")) {
        return nullptr;
    }
    if (!expect(TokenKind::RParen, "expected ')' after parameters")) {
        return nullptr;
    }
    if (!expect(TokenKind::Arrow, "expected '->' before return type")) {
        return nullptr;
    }
    if (!expect(TokenKind::Int, "expected 'int' return type")) {
        return nullptr;
    }
    fn->returnType = "int";
    fn->body = parseBlock();
    if (!fn->body) {
        return nullptr;
    }
    return fn;
}

std::unique_ptr<ast::Block> Parser::parseBlock() {
    if (!expect(TokenKind::LBrace, "expected '{' to start block")) {
        return nullptr;
    }
    auto block = std::make_unique<ast::Block>();
    while (!match(TokenKind::RBrace)) {
        if (peek().kind == TokenKind::Return) {
            auto ret = parseReturn();
            if (!ret) {
                return nullptr;
            }
            block->statements.push_back(std::move(ret));
        } else {
            diag_.error(peek().location, "expected 'return' statement");
            return nullptr;
        }
    }
    return block;
}

std::unique_ptr<ast::ReturnStmt> Parser::parseReturn() {
    if (!expect(TokenKind::Return, "expected 'return'")) {
        return nullptr;
    }
    auto literal = parseIntegerLiteral();
    if (!literal) {
        return nullptr;
    }
    if (!expect(TokenKind::Semicolon, "expected ';' after return expression")) {
        return nullptr;
    }
    auto stmt = std::make_unique<ast::ReturnStmt>();
    stmt->value = std::move(literal);
    return stmt;
}

std::unique_ptr<ast::IntegerLiteral> Parser::parseIntegerLiteral() {
    if (!expect(TokenKind::Integer, "expected integer literal")) {
        return nullptr;
    }
    auto lit = std::make_unique<ast::IntegerLiteral>();
    lit->value = std::strtol(previous().lexeme.c_str(), nullptr, 10);
    return lit;
}

} // namespace hy
