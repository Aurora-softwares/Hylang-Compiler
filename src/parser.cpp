#include "parser.hpp"

#include "util.hpp"

#include <cstdlib>

namespace hyc {

Parser::Parser(const std::vector<Token>& tokens, Diagnostics& diags)
    : diags_(diags), tokens_(tokens) {}

std::unique_ptr<Program> Parser::parse_program() {
    auto program = std::make_unique<Program>();
    while (!is(TokenKind::EndOfFile)) {
        if (auto decl = parse_declaration()) {
            program->decls.push_back(std::move(decl));
        } else {
            advance();
        }
    }
    return program;
}

const Token& Parser::peek(std::size_t offset) const {
    if (index_ + offset >= tokens_.size()) {
        return tokens_.back();
    }
    return tokens_[index_ + offset];
}

bool Parser::is(TokenKind kind, std::size_t offset) const {
    return peek(offset).kind == kind;
}

const Token& Parser::advance() {
    const Token& tok = peek();
    if (!is(TokenKind::EndOfFile)) {
        ++index_;
    }
    return tok;
}

bool Parser::match(TokenKind kind) {
    if (is(kind)) {
        advance();
        return true;
    }
    return false;
}

const Token& Parser::expect(TokenKind kind, const char* message) {
    if (!is(kind)) {
        diags_.error(peek().location, message);
    }
    return advance();
}

TypeAnnotation Parser::parse_type() {
    const Token& tok = expect(TokenKind::KwInt, "expected type 'Int'");
    TypeAnnotation ann;
    ann.kind = SimpleTypeKind::Int;
    ann.loc = tok.location;
    return ann;
}

std::unique_ptr<Decl> Parser::parse_declaration() {
    if (is(TokenKind::KwVar)) {
        return parse_var_declaration();
    }
    if (is(TokenKind::KwFunction)) {
        return parse_function_declaration();
    }
    diags_.error(peek().location, "expected declaration");
    return nullptr;
}

std::unique_ptr<Decl> Parser::parse_var_declaration() {
    const Token& kw = expect(TokenKind::KwVar, "expected 'Var'");
    TypeAnnotation type = parse_type();
    const Token& name_tok = expect(TokenKind::Identifier, "expected identifier");
    expect(TokenKind::Equal, "expected '='");
    auto init = parse_expression();
    expect(TokenKind::Semicolon, "expected ';'");

    if (!init) {
        diags_.error(name_tok.location, "expected initializer expression");
        return nullptr;
    }

    return std::make_unique<GlobalVarDecl>(type, name_tok.text, std::move(init),
                                           kw.location);
}

std::unique_ptr<FunctionDecl> Parser::parse_function_declaration() {
    const Token& kw = expect(TokenKind::KwFunction, "expected 'Function'");
    const Token& name_tok = expect(TokenKind::Identifier, "expected function name");
    expect(TokenKind::LParen, "expected '('");
    std::vector<Param> params;
    if (!is(TokenKind::RParen)) {
        params = parse_param_list();
    }
    expect(TokenKind::RParen, "expected ')'");
    auto body = parse_block();

    TypeAnnotation ret_type;
    ret_type.kind = SimpleTypeKind::Int;
    ret_type.loc = kw.location;

    SourceLocation end = body.empty() ? kw.location : body.back()->loc;
    return std::make_unique<FunctionDecl>(name_tok.text, std::move(params),
                                          std::move(body), ret_type, kw.location,
                                          end);
}

Param Parser::parse_param() {
    TypeAnnotation type = parse_type();
    const Token& name_tok = expect(TokenKind::Identifier, "expected parameter name");
    Param param;
    param.type = type;
    param.name = name_tok.text;
    param.loc = name_tok.location;
    return param;
}

std::vector<Param> Parser::parse_param_list() {
    std::vector<Param> params;
    params.push_back(parse_param());
    while (match(TokenKind::Comma)) {
        params.push_back(parse_param());
    }
    return params;
}

std::vector<std::unique_ptr<Stmt>> Parser::parse_block() {
    expect(TokenKind::LBrace, "expected '{'");
    std::vector<std::unique_ptr<Stmt>> statements;
    while (!is(TokenKind::RBrace) && !is(TokenKind::EndOfFile)) {
        if (is(TokenKind::KwVar)) {
            auto decl = parse_var_statement();
            if (decl) {
                statements.push_back(std::move(decl));
            }
            continue;
        }
        if (auto stmt = parse_statement()) {
            statements.push_back(std::move(stmt));
        } else {
            advance();
        }
    }
    expect(TokenKind::RBrace, "expected '}'");
    return statements;
}

std::unique_ptr<Stmt> Parser::parse_statement() {
    if (is(TokenKind::KwReturn)) {
        return parse_return_statement();
    }
    return parse_expression_statement();
}

std::unique_ptr<Stmt> Parser::parse_var_statement() {
    const Token& kw = expect(TokenKind::KwVar, "expected 'Var'");
    TypeAnnotation type = parse_type();
    const Token& name_tok = expect(TokenKind::Identifier, "expected identifier");
    expect(TokenKind::Equal, "expected '='");
    auto init = parse_expression();
    expect(TokenKind::Semicolon, "expected ';'");
    if (!init) {
        diags_.error(name_tok.location, "expected initializer expression");
        return nullptr;
    }
    return std::make_unique<VarDeclStmt>(type, name_tok.text, std::move(init),
                                         kw.location);
}

std::unique_ptr<Stmt> Parser::parse_return_statement() {
    const Token& kw = expect(TokenKind::KwReturn, "expected 'Return'");
    std::unique_ptr<Expr> expr;
    if (!is(TokenKind::Semicolon)) {
        expr = parse_expression();
    }
    expect(TokenKind::Semicolon, "expected ';'");
    return std::make_unique<ReturnStmt>(std::move(expr), kw.location);
}

std::unique_ptr<Stmt> Parser::parse_expression_statement() {
    auto expr = parse_expression();
    expect(TokenKind::Semicolon, "expected ';'");
    if (!expr) {
        diags_.error(peek().location, "expected expression");
        return nullptr;
    }
    return std::make_unique<ExprStmt>(std::move(expr), expr->loc);
}

std::unique_ptr<Expr> Parser::parse_expression() {
    return parse_assignment();
}

std::unique_ptr<Expr> Parser::parse_assignment() {
    auto left = parse_primary();
    if (!left) {
        return nullptr;
    }

    if (left->kind == Expr::Kind::Identifier && is(TokenKind::Equal)) {
        auto* ident = static_cast<IdentifierExpr*>(left.get());
        advance();
        auto value = parse_expression();
        if (!value) {
            diags_.error(peek().location, "expected expression after '='");
            return nullptr;
        }
        return std::make_unique<AssignmentExpr>(ident->name, std::move(value),
                                                 left->loc);
    }

    return left;
}

std::unique_ptr<Expr> Parser::parse_primary() {
    if (is(TokenKind::Identifier)) {
        const Token& tok = advance();
        if (is(TokenKind::LParen)) {
            advance();
            auto call = std::make_unique<CallExpr>(tok.text, tok.location);
            if (!is(TokenKind::RParen)) {
                call->args.push_back(parse_expression());
                while (match(TokenKind::Comma)) {
                    call->args.push_back(parse_expression());
                }
            }
            expect(TokenKind::RParen, "expected ')'");
            return call;
        }
        return std::make_unique<IdentifierExpr>(tok.text, tok.location);
    }

    if (is(TokenKind::Integer)) {
        const Token& tok = advance();
        int value = std::atoi(tok.text.c_str());
        return std::make_unique<IntegerLiteralExpr>(value, tok.location);
    }

    if (match(TokenKind::LParen)) {
        auto expr = parse_expression();
        expect(TokenKind::RParen, "expected ')'");
        return expr;
    }

    diags_.error(peek().location, "expected expression");
    return nullptr;
}

} // namespace hyc
