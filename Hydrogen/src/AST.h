#pragma once

#include <memory>
#include <string>
#include <vector>

namespace hy::ast {

struct Node {
    virtual ~Node() = default;
};

struct Expr : Node {
};

struct IntegerLiteral : Expr {
    int value;
};

struct Stmt : Node {
};

struct ReturnStmt : Stmt {
    std::unique_ptr<Expr> value;
};

struct VarDecl : Stmt {
    std::string name;
    // TODO: Extend with type annotations, initializer expressions, mutability, etc.
};

struct Block : Node {
    std::vector<std::unique_ptr<Stmt>> statements;
};

struct FuncDecl : Node {
    std::string name;
    std::string returnType;
    std::unique_ptr<Block> body;
};

struct NamespaceDecl : Node {
    std::string name;
    std::vector<std::unique_ptr<FuncDecl>> functions;
};

struct Module : Node {
    std::unique_ptr<NamespaceDecl> ns;
};

} // namespace hy::ast
