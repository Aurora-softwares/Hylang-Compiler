#include "parser.hpp"

#include <cstdlib>
#include <sstream>

namespace hyc {

Parser::Parser(const std::vector<Token> &tokens, std::string source, Diagnostics &diag)
    : m_tokens(tokens), m_source(std::move(source)), m_diag(diag) {
    std::size_t start = 0;
    while (start < m_source.size()) {
        auto end = m_source.find('\n', start);
        if (end == std::string::npos) {
            end = m_source.size();
        }
        m_lines.emplace_back(m_source.substr(start, end - start));
        start = end + 1;
    }
    if (m_lines.empty()) {
        m_lines.emplace_back("");
    }
}

const Token &Parser::peek(std::size_t offset) const {
    std::size_t idx = m_index + offset;
    if (idx >= m_tokens.size()) {
        return m_tokens.back();
    }
    return m_tokens[idx];
}

bool Parser::check(TokenKind kind, std::size_t offset) const {
    return peek(offset).kind == kind;
}

bool Parser::match(TokenKind kind) {
    if (check(kind)) {
        ++m_index;
        return true;
    }
    return false;
}

const Token &Parser::consume(TokenKind kind, const std::string &message) {
    if (check(kind)) {
        return m_tokens[m_index++];
    }
    const Token &token = peek();
    m_diag.error(token.location, lineText(token.location.line), token.location.column - 1,
                 token.lexeme.empty() ? 1u : static_cast<unsigned>(token.lexeme.size()), message);
    return token;
}

std::string Parser::lineText(unsigned line) const {
    if (line == 0 || line > m_lines.size()) {
        return "";
    }
    return m_lines[line - 1];
}

void Parser::synchronize() {
    while (!check(TokenKind::EndOfFile)) {
        if (peek().kind == TokenKind::Semicolon) {
            ++m_index;
            return;
        }
        switch (peek().kind) {
        case TokenKind::KwVar:
        case TokenKind::KwFunction:
        case TokenKind::KwReturn:
            return;
        default:
            ++m_index;
            break;
        }
    }
}

Program Parser::parseProgram() {
    Program program;
    while (!check(TokenKind::EndOfFile)) {
        auto decl = parseDeclaration();
        if (decl) {
            program.declarations.push_back(std::move(decl));
        } else {
            synchronize();
        }
    }
    return program;
}

std::unique_ptr<Decl> Parser::parseDeclaration() {
    if (check(TokenKind::KwVar)) {
        return parseGlobalVar();
    }
    if (check(TokenKind::KwFunction)) {
        return parseFunction();
    }
    const Token &tok = peek();
    m_diag.error(tok.location, lineText(tok.location.line), tok.location.column - 1,
                 tok.lexeme.empty() ? 1u : static_cast<unsigned>(tok.lexeme.size()), "expected declaration");
    ++m_index;
    return nullptr;
}

std::unique_ptr<VarDecl> Parser::parseGlobalVar() {
    auto stmt = parseVarDeclStmt(true);
    if (!stmt) {
        return nullptr;
    }
    auto decl = std::make_unique<VarDecl>();
    decl->location = stmt->location;
    decl->statement = std::move(stmt);
    return decl;
}

Type Parser::parseType() {
    const Token &tok = consume(TokenKind::KwInt, "expected type 'Int'");
    (void)tok;
    Type type;
    type.kind = TypeKind::Int;
    return type;
}

std::unique_ptr<VarDeclStmt> Parser::parseVarDeclStmt(bool isGlobal) {
    const Token &varTok = consume(TokenKind::KwVar, "expected 'Var'");
    Type type = parseType();
    const Token &nameTok = consume(TokenKind::Identifier, "expected identifier");
    consume(TokenKind::Equal, "expected '=' in variable declaration");
    auto init = parseExpression();
    consume(TokenKind::Semicolon, "expected ';' after variable declaration");
    auto stmt = std::make_unique<VarDeclStmt>();
    stmt->location = varTok.location;
    stmt->type = type;
    stmt->name = nameTok.lexeme;
    stmt->initializer = std::move(init);
    stmt->isGlobal = isGlobal;
    return stmt;
}

std::unique_ptr<FunctionDecl> Parser::parseFunction() {
    const Token &fnTok = consume(TokenKind::KwFunction, "expected 'Function'");
    const Token &nameTok = consume(TokenKind::Identifier, "expected function name");
    auto func = std::make_unique<FunctionDecl>();
    func->location = fnTok.location;
    func->name = nameTok.lexeme;
    func->returnType.kind = TypeKind::Int;

    consume(TokenKind::LParen, "expected '(' after function name");
    if (!check(TokenKind::RParen)) {
        while (true) {
            Parameter param;
            param.type = parseType();
            const Token &paramName = consume(TokenKind::Identifier, "expected parameter name");
            param.name = paramName.lexeme;
            param.location = paramName.location;
            func->parameters.push_back(param);
            if (match(TokenKind::Comma)) {
                continue;
            }
            break;
        }
    }
    consume(TokenKind::RParen, "expected ')' after parameters");
    func->body = parseBlock();
    return func;
}

std::unique_ptr<BlockStmt> Parser::parseBlock() {
    const Token &lbrace = consume(TokenKind::LBrace, "expected '{'");
    auto block = std::make_unique<BlockStmt>();
    block->location = lbrace.location;
    while (!check(TokenKind::RBrace) && !check(TokenKind::EndOfFile)) {
        auto stmt = parseStatement();
        if (stmt) {
            block->statements.push_back(std::move(stmt));
        } else {
            synchronize();
        }
    }
    consume(TokenKind::RBrace, "expected '}'");
    return block;
}

std::unique_ptr<Stmt> Parser::parseStatement() {
    if (check(TokenKind::KwVar)) {
        return parseVarDeclStmt(false);
    }
    if (check(TokenKind::KwReturn)) {
        return parseReturnStmt();
    }
    return parseExprStmt();
}

std::unique_ptr<Stmt> Parser::parseReturnStmt() {
    const Token &retTok = consume(TokenKind::KwReturn, "expected 'Return'");
    auto stmt = std::make_unique<ReturnStmt>();
    stmt->location = retTok.location;
    if (!check(TokenKind::Semicolon)) {
        stmt->value = parseExpression();
    }
    consume(TokenKind::Semicolon, "expected ';' after return");
    return stmt;
}

std::unique_ptr<Stmt> Parser::parseExprStmt() {
    auto expr = parseExpression();
    const Token &semi = consume(TokenKind::Semicolon, "expected ';' after expression");
    auto stmt = std::make_unique<ExprStmt>();
    stmt->location = semi.location;
    stmt->expression = std::move(expr);
    return stmt;
}

std::unique_ptr<Expr> Parser::parseExpression() {
    return parseAssignment();
}

std::unique_ptr<Expr> Parser::parseAssignment() {
    auto expr = parseCall();
    if (match(TokenKind::Equal)) {
        const Token &eqTok = m_tokens[m_index - 1];
        auto value = parseAssignment();
        if (expr && expr->kind == Expr::Kind::Identifier) {
            auto ident = std::unique_ptr<IdentifierExpr>(static_cast<IdentifierExpr *>(expr.release()));
            auto assign = std::make_unique<AssignmentExpr>();
            assign->location = eqTok.location;
            assign->name = ident->name;
            assign->value = std::move(value);
            return assign;
        } else {
            const Token &token = peek();
            m_diag.error(eqTok.location, lineText(eqTok.location.line), eqTok.location.column - 1, 1,
                         "assignment target must be an identifier");
        }
    }
    return expr;
}

std::unique_ptr<Expr> Parser::parseCall() {
    auto primary = parsePrimary();
    while (match(TokenKind::LParen)) {
        auto calleeExpr = std::move(primary);
        auto call = std::make_unique<CallExpr>();
        call->location = calleeExpr ? calleeExpr->location : m_tokens[m_index - 1].location;
        if (!calleeExpr || calleeExpr->kind != Expr::Kind::Identifier) {
            if (calleeExpr) {
                m_diag.error(calleeExpr->location, lineText(calleeExpr->location.line),
                             calleeExpr->location.column - 1, 1, "only identifiers can be called");
            } else {
                const auto &tok = m_tokens[m_index - 1];
                m_diag.error(tok.location, lineText(tok.location.line), tok.location.column - 1, 1,
                             "invalid call expression");
            }
        }
        std::string callee;
        if (calleeExpr && calleeExpr->kind == Expr::Kind::Identifier) {
            callee = static_cast<IdentifierExpr *>(calleeExpr.get())->name;
        }
        call->callee = callee;
        if (!check(TokenKind::RParen)) {
            while (true) {
                call->arguments.push_back(parseExpression());
                if (match(TokenKind::Comma)) {
                    continue;
                }
                break;
            }
        }
        consume(TokenKind::RParen, "expected ')' after arguments");
        primary = std::move(call);
    }
    return primary;
}

std::unique_ptr<Expr> Parser::parsePrimary() {
    const Token &token = peek();
    if (match(TokenKind::Integer)) {
        auto expr = std::make_unique<IntegerLiteralExpr>();
        expr->location = token.location;
        expr->value = std::stoi(token.lexeme);
        return expr;
    }
    if (match(TokenKind::Identifier)) {
        auto expr = std::make_unique<IdentifierExpr>();
        expr->location = token.location;
        expr->name = token.lexeme;
        return expr;
    }
    if (match(TokenKind::KwPrint)) {
        auto expr = std::make_unique<IdentifierExpr>();
        expr->location = token.location;
        expr->name = "Print";
        return expr;
    }
    if (match(TokenKind::LParen)) {
        auto expr = parseExpression();
        consume(TokenKind::RParen, "expected ')' after expression");
        return expr;
    }
    m_diag.error(token.location, lineText(token.location.line), token.location.column - 1,
                 token.lexeme.empty() ? 1u : static_cast<unsigned>(token.lexeme.size()), "expected expression");
    ++m_index;
    auto dummy = std::make_unique<IntegerLiteralExpr>();
    dummy->location = token.location;
    dummy->value = 0;
    return dummy;
}

} // namespace hyc
