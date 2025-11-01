#pragma once

#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "util.hpp"

enum class SimpleType {
    Int
};

struct Expr {
    struct Identifier {
        std::string name;
    };

    struct IntegerLiteral {
        int value;
    };

    struct Assignment {
        std::string name;
        std::unique_ptr<Expr> value;
    };

    struct Call {
        std::string callee;
        std::vector<std::unique_ptr<Expr>> arguments;
    };

    std::variant<Identifier, IntegerLiteral, Assignment, Call> node;
    SourceLocation loc;
};

struct VarDecl {
    SimpleType type{SimpleType::Int};
    std::string name;
    std::unique_ptr<Expr> initializer;
    SourceLocation loc;
};

struct Statement {
    struct VarDeclStmt {
        VarDecl decl;
    };

    struct ExprStmt {
        std::unique_ptr<Expr> expr;
    };

    struct ReturnStmt {
        std::unique_ptr<Expr> value;
        bool hasValue{false};
    };

    std::variant<VarDeclStmt, ExprStmt, ReturnStmt> node;
    SourceLocation loc;
};

struct Parameter {
    SimpleType type{SimpleType::Int};
    std::string name;
    SourceLocation loc;
};

struct FunctionDecl {
    std::string name;
    std::vector<Parameter> parameters;
    std::vector<std::unique_ptr<Statement>> body;
    SourceLocation loc;
};

struct TopLevelDecl {
    struct VarDeclTop {
        VarDecl decl;
    };
    struct Function {
        std::unique_ptr<FunctionDecl> decl;
    };

    std::variant<VarDeclTop, Function> node;
};

struct Program {
    std::vector<std::unique_ptr<TopLevelDecl>> declarations;
};
