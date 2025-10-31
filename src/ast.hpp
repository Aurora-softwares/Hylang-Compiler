#pragma once

#include "tokens.hpp"

#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace hydrogenc {

enum class TypeKind {
    Int,
    Void,
    Invalid,
};

struct Type {
    TypeKind kind = TypeKind::Invalid;

    static Type Int() { return {TypeKind::Int}; }
    static Type Void() { return {TypeKind::Void}; }
    static Type Invalid() { return {TypeKind::Invalid}; }

    bool is_int() const { return kind == TypeKind::Int; }
    bool is_valid() const { return kind != TypeKind::Invalid; }
};

struct Expr {
    enum class Kind {
        Identifier,
        Integer,
        Call,
        Assignment,
    };

    explicit Expr(Kind k, SourceLocation loc) : kind(k), location(loc) {}
    virtual ~Expr() = default;

    Kind kind;
    SourceLocation location;
    Type resolved_type = Type::Invalid();
};

struct IdentifierExpr : Expr {
    std::string name;
    IdentifierExpr(std::string n, SourceLocation loc)
        : Expr(Kind::Identifier, loc), name(std::move(n)) {}
};

struct IntegerExpr : Expr {
    std::int32_t value;
    IntegerExpr(std::int32_t v, SourceLocation loc)
        : Expr(Kind::Integer, loc), value(v) {}
};

struct CallExpr : Expr {
    std::string callee;
    std::vector<std::unique_ptr<Expr>> arguments;
    CallExpr(std::string name, SourceLocation loc)
        : Expr(Kind::Call, loc), callee(std::move(name)) {}
};

struct AssignmentExpr : Expr {
    std::string name;
    std::unique_ptr<Expr> value;
    AssignmentExpr(std::string n, std::unique_ptr<Expr> v, SourceLocation loc)
        : Expr(Kind::Assignment, loc), name(std::move(n)), value(std::move(v)) {}
};

struct Stmt {
    enum class Kind {
        VarDecl,
        Expr,
        Return,
        Block,
    };

    explicit Stmt(Kind k, SourceLocation loc) : kind(k), location(loc) {}
    virtual ~Stmt() = default;

    Kind kind;
    SourceLocation location;
};

struct VarDeclStmt : Stmt {
    std::string name;
    Type type;
    std::unique_ptr<Expr> initializer;
    bool is_global = false;

    VarDeclStmt(std::string n, Type t, std::unique_ptr<Expr> init, SourceLocation loc)
        : Stmt(Kind::VarDecl, loc), name(std::move(n)), type(t), initializer(std::move(init)) {}
};

struct ExprStmt : Stmt {
    std::unique_ptr<Expr> expression;
    ExprStmt(std::unique_ptr<Expr> expr, SourceLocation loc)
        : Stmt(Kind::Expr, loc), expression(std::move(expr)) {}
};

struct ReturnStmt : Stmt {
    std::unique_ptr<Expr> expression;
    ReturnStmt(std::unique_ptr<Expr> expr, SourceLocation loc)
        : Stmt(Kind::Return, loc), expression(std::move(expr)) {}
};

struct BlockStmt : Stmt {
    std::vector<std::unique_ptr<Stmt>> statements;
    BlockStmt(SourceLocation loc)
        : Stmt(Kind::Block, loc) {}
};

struct Param {
    std::string name;
    Type type;
    SourceLocation location;
};

struct FunctionDefinition {
    std::string name;
    std::vector<Param> parameters;
    Type return_type = Type::Int();
    std::unique_ptr<BlockStmt> body;
    SourceLocation location;
};

struct Program {
    std::vector<std::unique_ptr<VarDeclStmt>> globals;
    std::vector<std::unique_ptr<FunctionDefinition>> functions;
};

} // namespace hydrogenc
