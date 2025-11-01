#pragma once

#include "tokens.hpp"

#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace hyc {

enum class SimpleTypeKind {
    Int,
};

struct TypeAnnotation {
    SimpleTypeKind kind = SimpleTypeKind::Int;
    SourceLocation loc;
};

struct Expr {
    enum class Kind {
        Identifier,
        Integer,
        Call,
        Assignment,
    };

    Kind kind;
    SourceLocation loc;
    explicit Expr(Kind k, SourceLocation loc) : kind(k), loc(std::move(loc)) {}
    virtual ~Expr() = default;
};

struct IdentifierExpr : Expr {
    std::string name;
    IdentifierExpr(const std::string& n, SourceLocation loc)
        : Expr(Kind::Identifier, std::move(loc)), name(n) {}
};

struct IntegerLiteralExpr : Expr {
    int value;
    IntegerLiteralExpr(int v, SourceLocation loc)
        : Expr(Kind::Integer, std::move(loc)), value(v) {}
};

struct CallExpr : Expr {
    std::string callee;
    std::vector<std::unique_ptr<Expr>> args;
    CallExpr(std::string name, SourceLocation loc)
        : Expr(Kind::Call, std::move(loc)), callee(std::move(name)) {}
};

struct AssignmentExpr : Expr {
    std::string target;
    std::unique_ptr<Expr> value;
    AssignmentExpr(std::string name, std::unique_ptr<Expr> val, SourceLocation loc)
        : Expr(Kind::Assignment, std::move(loc)), target(std::move(name)),
          value(std::move(val)) {}
};

struct Stmt {
    enum class Kind {
        Var,
        Expr,
        Return,
    };

    Kind kind;
    SourceLocation loc;
    Stmt(Kind k, SourceLocation loc) : kind(k), loc(std::move(loc)) {}
    virtual ~Stmt() = default;
};

struct VarDeclStmt : Stmt {
    TypeAnnotation type;
    std::string name;
    std::unique_ptr<Expr> initializer;
    VarDeclStmt(TypeAnnotation ty, std::string name, std::unique_ptr<Expr> init,
                SourceLocation loc)
        : Stmt(Kind::Var, std::move(loc)), type(std::move(ty)),
          name(std::move(name)), initializer(std::move(init)) {}
};

struct ExprStmt : Stmt {
    std::unique_ptr<Expr> expression;
    ExprStmt(std::unique_ptr<Expr> expr, SourceLocation loc)
        : Stmt(Kind::Expr, std::move(loc)), expression(std::move(expr)) {}
};

struct ReturnStmt : Stmt {
    std::unique_ptr<Expr> expression;
    ReturnStmt(std::unique_ptr<Expr> expr, SourceLocation loc)
        : Stmt(Kind::Return, std::move(loc)), expression(std::move(expr)) {}
};

struct Param {
    TypeAnnotation type;
    std::string name;
    SourceLocation loc;
};

struct Decl {
    enum class Kind {
        GlobalVar,
        Function,
    };

    Kind kind;
    SourceLocation loc;
    Decl(Kind k, SourceLocation loc) : kind(k), loc(std::move(loc)) {}
    virtual ~Decl() = default;
};

struct GlobalVarDecl : Decl {
    TypeAnnotation type;
    std::string name;
    std::unique_ptr<Expr> initializer;
    GlobalVarDecl(TypeAnnotation ty, std::string name, std::unique_ptr<Expr> init,
                  SourceLocation loc)
        : Decl(Kind::GlobalVar, std::move(loc)), type(std::move(ty)),
          name(std::move(name)), initializer(std::move(init)) {}
};

struct FunctionDecl : Decl {
    std::string name;
    std::vector<Param> params;
    std::vector<std::unique_ptr<Stmt>> body;
    TypeAnnotation return_type;
    SourceLocation end_loc;

    FunctionDecl(std::string name, std::vector<Param> params,
                 std::vector<std::unique_ptr<Stmt>> body, TypeAnnotation ret_type,
                 SourceLocation start, SourceLocation end)
        : Decl(Kind::Function, std::move(start)), name(std::move(name)),
          params(std::move(params)), body(std::move(body)),
          return_type(std::move(ret_type)), end_loc(std::move(end)) {}
};

struct Program {
    std::vector<std::unique_ptr<Decl>> decls;
};

} // namespace hyc
