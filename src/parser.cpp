#include "parser.hpp"

#include <iostream>
#include <stdexcept>

namespace {
SourceLocation locFromToken(const Token &tok) {
    return SourceLocation{tok.line, tok.column};
}
}

Parser::Parser(Lexer &lexer, DiagnosticsEngine &diag) : lexer_(lexer), diag_(diag) {}

const Token &Parser::peek() { return lexer_.peek(); }

Token Parser::consume() { return lexer_.next(); }

bool Parser::match(TokenKind kind) {
    if (peek().kind == kind) {
        consume();
        return true;
    }
    return false;
}

Token Parser::expect(TokenKind kind, const std::string &message) {
    Token tok = consume();
    if (tok.kind != kind) {
        diag_.error(tok.line, tok.column, message);
    }
    return tok;
}

std::unique_ptr<Program> Parser::parseProgram() {
    auto program = std::make_unique<Program>();
    while (peek().kind != TokenKind::EndOfFile) {
        auto decl = parseDeclaration();
        if (!decl) {
            break;
        }
        program->declarations.push_back(std::move(decl));
    }
    return program;
}

std::unique_ptr<TopLevelDecl> Parser::parseDeclaration() {
    if (peek().kind == TokenKind::KeywordVar) {
        return parseVarDecl();
    }
    if (peek().kind == TokenKind::KeywordFunction) {
        return parseFunctionDecl();
    }
    const Token &tok = peek();
    diag_.error(tok.line, tok.column, "expected declaration");
    consume();
    return nullptr;
}

std::unique_ptr<TopLevelDecl> Parser::parseVarDecl() {
    Token varTok = expect(TokenKind::KeywordVar, "expected 'Var'");
    SimpleType type = parseType();
    Token nameTok = expect(TokenKind::Identifier, "expected identifier");
    expect(TokenKind::Equal, "expected '=' after variable name");
    auto init = parseExpression();
    expect(TokenKind::Semicolon, "expected ';' after variable declaration");

    auto decl = std::make_unique<TopLevelDecl>();
    VarDecl var;
    var.type = type;
    var.name = nameTok.lexeme;
    var.initializer = std::move(init);
    var.loc = locFromToken(varTok);
    decl->node = TopLevelDecl::VarDeclTop{std::move(var)};
    return decl;
}

std::unique_ptr<TopLevelDecl> Parser::parseFunctionDecl() {
    Token funcTok = expect(TokenKind::KeywordFunction, "expected 'Function'");
    Token nameTok = expect(TokenKind::Identifier, "expected function name");
    expect(TokenKind::LParen, "expected '('");

    std::vector<Parameter> params;
    if (peek().kind != TokenKind::RParen) {
        while (true) {
            params.push_back(parseParameter());
            if (!match(TokenKind::Comma)) {
                break;
            }
        }
    }
    expect(TokenKind::RParen, "expected ')'");

    auto func = parseFunctionBody(nameTok.lexeme, locFromToken(funcTok));
    func->parameters = std::move(params);

    auto decl = std::make_unique<TopLevelDecl>();
    decl->node = TopLevelDecl::Function{std::move(func)};
    return decl;
}

std::unique_ptr<FunctionDecl> Parser::parseFunctionBody(std::string name, SourceLocation loc) {
    auto func = std::make_unique<FunctionDecl>();
    func->name = std::move(name);
    func->loc = loc;

    expect(TokenKind::LBrace, "expected '{' to start function body");
    while (peek().kind != TokenKind::RBrace && peek().kind != TokenKind::EndOfFile) {
        auto stmt = parseStatement();
        if (stmt) {
            func->body.push_back(std::move(stmt));
        }
    }
    expect(TokenKind::RBrace, "expected '}' to close function body");
    return func;
}

Parameter Parser::parseParameter() {
    Parameter param;
    param.type = parseType();
    Token nameTok = expect(TokenKind::Identifier, "expected parameter name");
    param.name = nameTok.lexeme;
    param.loc = locFromToken(nameTok);
    return param;
}

SimpleType Parser::parseType() {
    Token tok = consume();
    if (tok.kind != TokenKind::KeywordInt) {
        diag_.error(tok.line, tok.column, "expected type name");
    }
    return SimpleType::Int;
}

std::unique_ptr<Statement> Parser::parseStatement() {
    if (peek().kind == TokenKind::KeywordVar) {
        return parseVarDeclStmt();
    }
    if (peek().kind == TokenKind::KeywordReturn) {
        return parseReturnStmt();
    }
    return parseExprStmt();
}

std::unique_ptr<Statement> Parser::parseVarDeclStmt() {
    Token varTok = expect(TokenKind::KeywordVar, "expected 'Var'");
    SimpleType type = parseType();
    Token nameTok = expect(TokenKind::Identifier, "expected identifier");
    expect(TokenKind::Equal, "expected '=' after variable name");
    auto init = parseExpression();
    expect(TokenKind::Semicolon, "expected ';' after variable declaration");

    auto stmt = std::make_unique<Statement>();
    stmt->loc = locFromToken(varTok);
    VarDecl decl;
    decl.type = type;
    decl.name = nameTok.lexeme;
    decl.initializer = std::move(init);
    decl.loc = locFromToken(nameTok);
    stmt->node = Statement::VarDeclStmt{std::move(decl)};
    return stmt;
}

std::unique_ptr<Statement> Parser::parseReturnStmt() {
    Token retTok = expect(TokenKind::KeywordReturn, "expected 'Return'");
    auto stmt = std::make_unique<Statement>();
    stmt->loc = locFromToken(retTok);
    auto returnStmt = Statement::ReturnStmt{};
    if (peek().kind != TokenKind::Semicolon) {
        returnStmt.value = parseExpression();
        returnStmt.hasValue = true;
    }
    expect(TokenKind::Semicolon, "expected ';' after return statement");
    stmt->node = std::move(returnStmt);
    return stmt;
}

std::unique_ptr<Statement> Parser::parseExprStmt() {
    auto expr = parseExpression();
    Token semi = expect(TokenKind::Semicolon, "expected ';' after expression");
    (void)semi;
    auto stmt = std::make_unique<Statement>();
    stmt->loc = expr ? expr->loc : locFromToken(semi);
    Statement::ExprStmt exprStmt;
    exprStmt.expr = std::move(expr);
    stmt->node = std::move(exprStmt);
    return stmt;
}

std::unique_ptr<Expr> Parser::parseExpression() {
    return parseAssignment();
}

std::unique_ptr<Expr> Parser::parseAssignment() {
    auto lhs = parseCallOrPrimary();
    if (!lhs) {
        return nullptr;
    }
    if (peek().kind == TokenKind::Equal) {
        if (!std::holds_alternative<Expr::Identifier>(lhs->node)) {
            diag_.error(lhs->loc.line, lhs->loc.column, "left side of assignment must be an identifier");
        }
        consume();
        auto value = parseAssignment();
        auto expr = std::make_unique<Expr>();
        expr->loc = lhs->loc;
        Expr::Assignment assign;
        if (std::holds_alternative<Expr::Identifier>(lhs->node)) {
            assign.name = std::get<Expr::Identifier>(lhs->node).name;
        }
        assign.value = std::move(value);
        expr->node = std::move(assign);
        return expr;
    }
    return lhs;
}

std::unique_ptr<Expr> Parser::parseCallOrPrimary() {
    auto expr = parsePrimary();
    if (!expr) {
        return nullptr;
    }
    while (peek().kind == TokenKind::LParen) {
        if (!std::holds_alternative<Expr::Identifier>(expr->node)) {
            break;
        }
        consume();
        Expr::Call call;
        call.callee = std::get<Expr::Identifier>(expr->node).name;
        if (peek().kind != TokenKind::RParen) {
            while (true) {
                call.arguments.push_back(parseExpression());
                if (!match(TokenKind::Comma)) {
                    break;
                }
            }
        }
        expect(TokenKind::RParen, "expected ')' after arguments");
        auto callExpr = std::make_unique<Expr>();
        callExpr->loc = expr->loc;
        callExpr->node = std::move(call);
        expr = std::move(callExpr);
    }
    return expr;
}

std::unique_ptr<Expr> Parser::parsePrimary() {
    Token tok = consume();
    auto expr = std::make_unique<Expr>();
    expr->loc = locFromToken(tok);
    switch (tok.kind) {
    case TokenKind::Identifier: {
        Expr::Identifier ident;
        ident.name = tok.lexeme;
        expr->node = std::move(ident);
        return expr;
    }
    case TokenKind::Integer: {
        Expr::IntegerLiteral literal;
        literal.value = std::stoi(tok.lexeme);
        expr->node = std::move(literal);
        return expr;
    }
    case TokenKind::LParen: {
        auto inner = parseExpression();
        expect(TokenKind::RParen, "expected ')' to close expression");
        return inner;
    }
    default:
        diag_.error(tok.line, tok.column, "unexpected token in expression");
        return nullptr;
    }
}
