#include "parser.hpp"

#include <stdexcept>

namespace hydrogenc {

Parser::Parser(const std::vector<Token>& tokens, DiagnosticEngine& diag)
    : diag_(diag), tokens_(tokens) {}

std::unique_ptr<Program> Parser::parse_program() {
    auto program = std::make_unique<Program>();

    while (!check(TokenKind::EndOfFile)) {
        if (check(TokenKind::KeywordVar)) {
            auto decl = parse_global_var();
            if (!decl) {
                return nullptr;
            }
            program->globals.push_back(std::move(decl));
        } else if (check(TokenKind::KeywordFunction)) {
            auto fn = parse_function();
            if (!fn) {
                return nullptr;
            }
            program->functions.push_back(std::move(fn));
        } else {
            const auto& tok = current();
            diag_.report({DiagnosticLevel::Error, tok.location, "expected declaration", tok.lexeme.size()});
            return nullptr;
        }
    }

    return program;
}

const Token& Parser::current() const {
    return tokens_[index_];
}

bool Parser::check(TokenKind kind) const {
    return current().kind == kind;
}

bool Parser::match(TokenKind kind) {
    if (check(kind)) {
        ++index_;
        return true;
    }
    return false;
}

const Token& Parser::consume(TokenKind kind, const std::string& message) {
    if (!check(kind)) {
        const auto& tok = current();
        diag_.report({DiagnosticLevel::Error, tok.location, message, tok.lexeme.size()});
        throw std::runtime_error("parse error");
    }
    return tokens_[index_++];
}

std::unique_ptr<VarDeclStmt> Parser::parse_global_var() {
    try {
        consume(TokenKind::KeywordVar, "expected 'Var'");
        Type type = parse_type();
        const auto& name_tok = consume(TokenKind::Identifier, "expected identifier");
        consume(TokenKind::Equal, "expected '='");
        auto init = parse_expression();
        consume(TokenKind::Semicolon, "expected ';'");
        auto decl = std::make_unique<VarDeclStmt>(name_tok.lexeme, type, std::move(init), name_tok.location);
        decl->is_global = true;
        return decl;
    } catch (const std::runtime_error&) {
        return nullptr;
    }
}

std::unique_ptr<FunctionDefinition> Parser::parse_function() {
    try {
        const auto& fn_tok = consume(TokenKind::KeywordFunction, "expected 'Function'");
        const auto& name_tok = consume(TokenKind::Identifier, "expected function name");
        consume(TokenKind::LParen, "expected '('");
        std::vector<Param> params;
        if (!check(TokenKind::RParen)) {
            while (true) {
                Type param_type = parse_type();
                const auto& param_name = consume(TokenKind::Identifier, "expected parameter name");
                params.push_back({param_name.lexeme, param_type, param_name.location});
                if (match(TokenKind::Comma)) {
                    continue;
                }
                break;
            }
        }
        consume(TokenKind::RParen, "expected ')'");
        auto body = parse_block();
        auto fn = std::make_unique<FunctionDefinition>();
        fn->name = name_tok.lexeme;
        fn->parameters = std::move(params);
        fn->body = std::move(body);
        fn->location = fn_tok.location;
        return fn;
    } catch (const std::runtime_error&) {
        return nullptr;
    }
}

Type Parser::parse_type() {
    const auto& tok = consume(TokenKind::KeywordInt, "expected type 'Int'");
    (void)tok;
    return Type::Int();
}

std::unique_ptr<BlockStmt> Parser::parse_block() {
    const auto& lbrace = consume(TokenKind::LBrace, "expected '{'");
    auto block = std::make_unique<BlockStmt>(lbrace.location);
    while (!check(TokenKind::RBrace) && !check(TokenKind::EndOfFile)) {
        auto stmt = parse_statement();
        if (!stmt) {
            return nullptr;
        }
        block->statements.push_back(std::move(stmt));
    }
    consume(TokenKind::RBrace, "expected '}'");
    return block;
}

std::unique_ptr<Stmt> Parser::parse_statement() {
    if (check(TokenKind::KeywordVar)) {
        return parse_var_decl(false);
    }
    if (check(TokenKind::KeywordReturn)) {
        return parse_return_statement();
    }
    return parse_expr_statement();
}

std::unique_ptr<VarDeclStmt> Parser::parse_var_decl(bool is_global) {
    consume(TokenKind::KeywordVar, "expected 'Var'");
    Type type = parse_type();
    const auto& name_tok = consume(TokenKind::Identifier, "expected identifier");
    consume(TokenKind::Equal, "expected '='");
    auto init = parse_expression();
    consume(TokenKind::Semicolon, "expected ';'");
    auto decl = std::make_unique<VarDeclStmt>(name_tok.lexeme, type, std::move(init), name_tok.location);
    decl->is_global = is_global;
    return decl;
}

std::unique_ptr<Stmt> Parser::parse_return_statement() {
    const auto& ret_tok = consume(TokenKind::KeywordReturn, "expected 'Return'");
    if (check(TokenKind::Semicolon)) {
        consume(TokenKind::Semicolon, "expected ';'");
        return std::make_unique<ReturnStmt>(nullptr, ret_tok.location);
    }
    auto value = parse_expression();
    consume(TokenKind::Semicolon, "expected ';'");
    return std::make_unique<ReturnStmt>(std::move(value), ret_tok.location);
}

std::unique_ptr<Stmt> Parser::parse_expr_statement() {
    auto expr = parse_expression();
    consume(TokenKind::Semicolon, "expected ';'");
    return std::make_unique<ExprStmt>(std::move(expr), expr->location);
}

std::unique_ptr<Expr> Parser::parse_expression() {
    return parse_assignment();
}

std::unique_ptr<Expr> Parser::parse_assignment() {
    auto left = parse_call_or_primary();
    if (left->kind == Expr::Kind::Identifier && match(TokenKind::Equal)) {
        auto rhs = parse_expression();
        auto ident = static_cast<IdentifierExpr*>(left.get());
        return std::make_unique<AssignmentExpr>(ident->name, std::move(rhs), left->location);
    }
    return left;
}

std::unique_ptr<Expr> Parser::parse_call_or_primary() {
    auto expr = parse_primary();
    while (match(TokenKind::LParen)) {
        if (expr->kind != Expr::Kind::Identifier) {
            diag_.report({DiagnosticLevel::Error, expr->location, "invalid call target", 1});
            throw std::runtime_error("parse error");
        }
        auto call = std::make_unique<CallExpr>(static_cast<IdentifierExpr*>(expr.get())->name, expr->location);
        if (!check(TokenKind::RParen)) {
            while (true) {
                call->arguments.push_back(parse_expression());
                if (match(TokenKind::Comma)) {
                    continue;
                }
                break;
            }
        }
        consume(TokenKind::RParen, "expected ')'");
        expr = std::move(call);
    }
    return expr;
}

std::unique_ptr<Expr> Parser::parse_primary() {
    const auto& tok = current();
    if (match(TokenKind::Identifier)) {
        return std::make_unique<IdentifierExpr>(tok.lexeme, tok.location);
    }
    if (check(TokenKind::KeywordPrint)) {
        const auto& kw = consume(TokenKind::KeywordPrint, "expected 'Print'");
        return std::make_unique<IdentifierExpr>("Print", kw.location);
    }
    if (match(TokenKind::Integer)) {
        return std::make_unique<IntegerExpr>(tok.int_value, tok.location);
    }
    if (match(TokenKind::LParen)) {
        auto expr = parse_expression();
        consume(TokenKind::RParen, "expected ')'");
        return expr;
    }

    diag_.report({DiagnosticLevel::Error, tok.location, "unexpected token in expression", tok.lexeme.size()});
    throw std::runtime_error("parse error");
}

} // namespace hydrogenc
