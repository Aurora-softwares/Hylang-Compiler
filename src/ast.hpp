#pragma once

#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "tokens.hpp"

namespace hyc {

enum class TypeKind {
    Int,
};

struct Type {
    TypeKind kind = TypeKind::Int;
};

struct Expr {
    enum class Kind {
        IntegerLiteral,
        Identifier,
        Assignment,
        Call,
    } kind;
    SourceLocation location;
    virtual ~Expr() = default;
};

struct IntegerLiteralExpr : Expr {
    int value = 0;
    IntegerLiteralExpr() { kind = Kind::IntegerLiteral; }
};

struct IdentifierExpr : Expr {
    std::string name;
    IdentifierExpr() { kind = Kind::Identifier; }
};

struct AssignmentExpr : Expr {
    std::string name;
    std::unique_ptr<Expr> value;
    AssignmentExpr() { kind = Kind::Assignment; }
};

struct CallExpr : Expr {
    std::string callee;
    std::vector<std::unique_ptr<Expr>> arguments;
    CallExpr() { kind = Kind::Call; }
};

struct Stmt {
    enum class Kind {
        VarDecl,
        ExprStmt,
        Return,
        Block,
    } kind;
    SourceLocation location;
    virtual ~Stmt() = default;
};

struct VarDeclStmt : Stmt {
    std::string name;
    Type type;
    std::unique_ptr<Expr> initializer;
    bool isGlobal = false;
    VarDeclStmt() { kind = Kind::VarDecl; }
};

struct ExprStmt : Stmt {
    std::unique_ptr<Expr> expression;
    ExprStmt() { kind = Kind::ExprStmt; }
};

struct ReturnStmt : Stmt {
    std::unique_ptr<Expr> value;
    ReturnStmt() { kind = Kind::Return; }
};

struct BlockStmt : Stmt {
    std::vector<std::unique_ptr<Stmt>> statements;
    BlockStmt() { kind = Kind::Block; }
};

struct Parameter {
    std::string name;
    Type type;
    SourceLocation location;
};

struct Decl {
    enum class Kind {
        Var,
        Function,
    } kind;
    SourceLocation location;
    virtual ~Decl() = default;
};

struct VarDecl : Decl {
    std::unique_ptr<VarDeclStmt> statement;
    VarDecl() { kind = Kind::Var; }
};

struct FunctionDecl : Decl {
    std::string name;
    std::vector<Parameter> parameters;
    Type returnType;
    std::unique_ptr<BlockStmt> body;
    FunctionDecl() { kind = Kind::Function; }
};

struct Program {
    std::vector<std::unique_ptr<Decl>> declarations;
};

} // namespace hyc
