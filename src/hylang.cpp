#include "hylang/hylang.hpp"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <iostream>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <variant>
#include <vector>

namespace hylang {
namespace {

using std::string;
using std::unique_ptr;
using std::vector;
namespace fs = std::filesystem;

struct DiagnosticBag {
    std::vector<Diagnostic> items;

    void add(const fs::path& file, int line, int column, std::string message) {
        items.push_back(Diagnostic{file, line, column, std::move(message)});
    }

    bool has_errors() const {
        return !items.empty();
    }

    void append(std::vector<Diagnostic> diagnostics) {
        items.insert(items.end(),
                     std::make_move_iterator(diagnostics.begin()),
                     std::make_move_iterator(diagnostics.end()));
    }
};

string trim(string value) {
    const auto not_space = [](unsigned char ch) { return !std::isspace(ch); };
    value.erase(value.begin(),
                std::find_if(value.begin(), value.end(), not_space));
    value.erase(std::find_if(value.rbegin(), value.rend(), not_space).base(), value.end());
    return value;
}

bool starts_with(const string& value, const string& prefix) {
    return value.rfind(prefix, 0) == 0;
}

string join_qualified(const vector<string>& parts) {
    std::ostringstream builder;
    for (std::size_t index = 0; index < parts.size(); ++index) {
        if (index > 0) {
            builder << '.';
        }
        builder << parts[index];
    }
    return builder.str();
}

enum class TokenKind {
    EndOfFile,
    Identifier,
    Number,
    StringLiteral,
    OpenParen,
    CloseParen,
    OpenBrace,
    CloseBrace,
    OpenBracket,
    CloseBracket,
    Semicolon,
    Comma,
    Dot,
    Plus,
    Minus,
    Star,
    Slash,
    Bang,
    Equals,
    EqualsEquals,
    BangEquals,
    Less,
    LessEquals,
    Greater,
    GreaterEquals,
    AmpAmp,
    PipePipe,
    Using,
    Namespace,
    Class,
    Public,
    Private,
    Protected,
    Internal,
    Static,
    Void,
    Int,
    StringKeyword,
    Bool,
    True,
    False,
    Null,
    If,
    Else,
    While,
    Return,
    New,
    This,
};

struct Token {
    TokenKind kind = TokenKind::EndOfFile;
    string text;
    int line = 1;
    int column = 1;
};

class Lexer {
public:
    Lexer(fs::path file, string source, DiagnosticBag& diagnostics)
        : file_(std::move(file)), source_(std::move(source)), diagnostics_(diagnostics) {}

    vector<Token> lex() {
        vector<Token> tokens;
        while (true) {
            skip_whitespace_and_comments();
            if (is_at_end()) {
                tokens.push_back(make_token(TokenKind::EndOfFile, ""));
                break;
            }

            const char current = peek();
            if (std::isalpha(static_cast<unsigned char>(current)) || current == '_') {
                tokens.push_back(lex_identifier_or_keyword());
                continue;
            }

            if (std::isdigit(static_cast<unsigned char>(current))) {
                tokens.push_back(lex_number());
                continue;
            }

            if (current == '"') {
                tokens.push_back(lex_string());
                continue;
            }

            const int line = line_;
            const int column = column_;
            advance();
            switch (current) {
                case '(':
                    tokens.push_back(Token{TokenKind::OpenParen, "(", line, column});
                    break;
                case ')':
                    tokens.push_back(Token{TokenKind::CloseParen, ")", line, column});
                    break;
                case '{':
                    tokens.push_back(Token{TokenKind::OpenBrace, "{", line, column});
                    break;
                case '}':
                    tokens.push_back(Token{TokenKind::CloseBrace, "}", line, column});
                    break;
                case '[':
                    tokens.push_back(Token{TokenKind::OpenBracket, "[", line, column});
                    break;
                case ']':
                    tokens.push_back(Token{TokenKind::CloseBracket, "]", line, column});
                    break;
                case ';':
                    tokens.push_back(Token{TokenKind::Semicolon, ";", line, column});
                    break;
                case ',':
                    tokens.push_back(Token{TokenKind::Comma, ",", line, column});
                    break;
                case '.':
                    tokens.push_back(Token{TokenKind::Dot, ".", line, column});
                    break;
                case '+':
                    tokens.push_back(Token{TokenKind::Plus, "+", line, column});
                    break;
                case '-':
                    tokens.push_back(Token{TokenKind::Minus, "-", line, column});
                    break;
                case '*':
                    tokens.push_back(Token{TokenKind::Star, "*", line, column});
                    break;
                case '/':
                    tokens.push_back(Token{TokenKind::Slash, "/", line, column});
                    break;
                case '!':
                    if (match('=')) {
                        tokens.push_back(Token{TokenKind::BangEquals, "!=", line, column});
                    } else {
                        tokens.push_back(Token{TokenKind::Bang, "!", line, column});
                    }
                    break;
                case '=':
                    if (match('=')) {
                        tokens.push_back(Token{TokenKind::EqualsEquals, "==", line, column});
                    } else {
                        tokens.push_back(Token{TokenKind::Equals, "=", line, column});
                    }
                    break;
                case '<':
                    if (match('=')) {
                        tokens.push_back(Token{TokenKind::LessEquals, "<=", line, column});
                    } else {
                        tokens.push_back(Token{TokenKind::Less, "<", line, column});
                    }
                    break;
                case '>':
                    if (match('=')) {
                        tokens.push_back(Token{TokenKind::GreaterEquals, ">=", line, column});
                    } else {
                        tokens.push_back(Token{TokenKind::Greater, ">", line, column});
                    }
                    break;
                case '&':
                    if (match('&')) {
                        tokens.push_back(Token{TokenKind::AmpAmp, "&&", line, column});
                    } else {
                        diagnostics_.add(file_, line, column, "Unexpected '&'. Did you mean '&&'?");
                    }
                    break;
                case '|':
                    if (match('|')) {
                        tokens.push_back(Token{TokenKind::PipePipe, "||", line, column});
                    } else {
                        diagnostics_.add(file_, line, column, "Unexpected '|'. Did you mean '||'?");
                    }
                    break;
                default:
                    diagnostics_.add(file_, line, column, "Unexpected character '" + string(1, current) + "'");
                    break;
            }
        }

        return tokens;
    }

private:
    Token make_token(TokenKind kind, string text, int line = -1, int column = -1) const {
        return Token{kind, std::move(text), line == -1 ? line_ : line, column == -1 ? column_ : column};
    }

    bool is_at_end() const {
        return index_ >= source_.size();
    }

    char peek() const {
        return is_at_end() ? '\0' : source_[index_];
    }

    char peek_next() const {
        return index_ + 1 >= source_.size() ? '\0' : source_[index_ + 1];
    }

    char advance() {
        if (is_at_end()) {
            return '\0';
        }
        const char ch = source_[index_++];
        if (ch == '\n') {
            ++line_;
            column_ = 1;
        } else {
            ++column_;
        }
        return ch;
    }

    bool match(char expected) {
        if (is_at_end() || source_[index_] != expected) {
            return false;
        }
        advance();
        return true;
    }

    void skip_whitespace_and_comments() {
        while (!is_at_end()) {
            const char ch = peek();
            if (std::isspace(static_cast<unsigned char>(ch))) {
                advance();
                continue;
            }
            if (ch == '/' && peek_next() == '/') {
                while (!is_at_end() && peek() != '\n') {
                    advance();
                }
                continue;
            }
            break;
        }
    }

    Token lex_identifier_or_keyword() {
        const int line = line_;
        const int column = column_;
        string text;
        while (!is_at_end()) {
            const char ch = peek();
            if (std::isalnum(static_cast<unsigned char>(ch)) || ch == '_') {
                text.push_back(advance());
            } else {
                break;
            }
        }

        static const std::unordered_map<string, TokenKind> keywords = {
            {"using", TokenKind::Using},
            {"namespace", TokenKind::Namespace},
            {"class", TokenKind::Class},
            {"public", TokenKind::Public},
            {"private", TokenKind::Private},
            {"protected", TokenKind::Protected},
            {"internal", TokenKind::Internal},
            {"static", TokenKind::Static},
            {"void", TokenKind::Void},
            {"int", TokenKind::Int},
            {"string", TokenKind::StringKeyword},
            {"bool", TokenKind::Bool},
            {"true", TokenKind::True},
            {"false", TokenKind::False},
            {"null", TokenKind::Null},
            {"if", TokenKind::If},
            {"else", TokenKind::Else},
            {"while", TokenKind::While},
            {"return", TokenKind::Return},
            {"new", TokenKind::New},
            {"this", TokenKind::This},
        };

        const auto found = keywords.find(text);
        if (found != keywords.end()) {
            return Token{found->second, text, line, column};
        }
        return Token{TokenKind::Identifier, text, line, column};
    }

    Token lex_number() {
        const int line = line_;
        const int column = column_;
        string text;
        while (!is_at_end() && std::isdigit(static_cast<unsigned char>(peek()))) {
            text.push_back(advance());
        }
        return Token{TokenKind::Number, text, line, column};
    }

    Token lex_string() {
        const int line = line_;
        const int column = column_;
        advance();
        string value;
        while (!is_at_end() && peek() != '"') {
            const char ch = advance();
            if (ch == '\\') {
                if (is_at_end()) {
                    diagnostics_.add(file_, line, column, "Unterminated string literal");
                    return Token{TokenKind::StringLiteral, value, line, column};
                }
                const char escaped = advance();
                switch (escaped) {
                    case 'n':
                        value.push_back('\n');
                        break;
                    case 't':
                        value.push_back('\t');
                        break;
                    case '"':
                        value.push_back('"');
                        break;
                    case '\\':
                        value.push_back('\\');
                        break;
                    default:
                        diagnostics_.add(file_, line, column, "Unsupported escape sequence");
                        value.push_back(escaped);
                        break;
                }
                continue;
            }
            value.push_back(ch);
        }

        if (is_at_end()) {
            diagnostics_.add(file_, line, column, "Unterminated string literal");
            return Token{TokenKind::StringLiteral, value, line, column};
        }

        advance();
        return Token{TokenKind::StringLiteral, value, line, column};
    }

    fs::path file_;
    string source_;
    DiagnosticBag& diagnostics_;
    std::size_t index_ = 0;
    int line_ = 1;
    int column_ = 1;
};

struct TypeSyntax {
    vector<string> name_parts;
    int array_rank = 0;
    int line = 1;
    int column = 1;
};

enum class ModifierKind {
    Public,
    Private,
    Protected,
    Internal,
    Static,
};

struct ParameterSyntax {
    TypeSyntax type;
    string name;
    int line = 1;
    int column = 1;
};

struct ExpressionSyntax {
    virtual ~ExpressionSyntax() = default;
    int line = 1;
    int column = 1;
};

struct LiteralExpressionSyntax final : ExpressionSyntax {
    std::variant<std::nullptr_t, int64_t, bool, string> value;
};

struct NameExpressionSyntax final : ExpressionSyntax {
    string name;
};

struct ThisExpressionSyntax final : ExpressionSyntax {};

struct AssignmentExpressionSyntax final : ExpressionSyntax {
    unique_ptr<ExpressionSyntax> target;
    unique_ptr<ExpressionSyntax> expression;
};

struct UnaryExpressionSyntax final : ExpressionSyntax {
    TokenKind op = TokenKind::Plus;
    unique_ptr<ExpressionSyntax> operand;
};

struct BinaryExpressionSyntax final : ExpressionSyntax {
    unique_ptr<ExpressionSyntax> left;
    TokenKind op = TokenKind::Plus;
    unique_ptr<ExpressionSyntax> right;
};

struct MemberAccessExpressionSyntax final : ExpressionSyntax {
    unique_ptr<ExpressionSyntax> target;
    string member_name;
};

struct InvocationExpressionSyntax final : ExpressionSyntax {
    unique_ptr<ExpressionSyntax> callee;
    vector<unique_ptr<ExpressionSyntax>> arguments;
};

struct ObjectCreationExpressionSyntax final : ExpressionSyntax {
    TypeSyntax type;
    vector<unique_ptr<ExpressionSyntax>> arguments;
};

struct StatementSyntax {
    virtual ~StatementSyntax() = default;
    int line = 1;
    int column = 1;
};

struct BlockStatementSyntax final : StatementSyntax {
    vector<unique_ptr<StatementSyntax>> statements;
};

struct VariableDeclarationStatementSyntax final : StatementSyntax {
    TypeSyntax type;
    string name;
    unique_ptr<ExpressionSyntax> initializer;
};

struct ExpressionStatementSyntax final : StatementSyntax {
    unique_ptr<ExpressionSyntax> expression;
};

struct IfStatementSyntax final : StatementSyntax {
    unique_ptr<ExpressionSyntax> condition;
    unique_ptr<StatementSyntax> then_statement;
    unique_ptr<StatementSyntax> else_statement;
};

struct WhileStatementSyntax final : StatementSyntax {
    unique_ptr<ExpressionSyntax> condition;
    unique_ptr<StatementSyntax> body;
};

struct ReturnStatementSyntax final : StatementSyntax {
    unique_ptr<ExpressionSyntax> expression;
};

struct MemberSyntax {
    virtual ~MemberSyntax() = default;
    vector<ModifierKind> modifiers;
    int line = 1;
    int column = 1;
};

struct FieldDeclarationSyntax final : MemberSyntax {
    TypeSyntax type;
    string name;
};

struct MethodDeclarationSyntax final : MemberSyntax {
    TypeSyntax return_type;
    string name;
    vector<ParameterSyntax> parameters;
    unique_ptr<BlockStatementSyntax> body;
};

struct ConstructorDeclarationSyntax final : MemberSyntax {
    string name;
    vector<ParameterSyntax> parameters;
    unique_ptr<BlockStatementSyntax> body;
};

struct ClassDeclarationSyntax {
    vector<ModifierKind> modifiers;
    string namespace_name;
    string name;
    vector<unique_ptr<MemberSyntax>> members;
    int line = 1;
    int column = 1;
};

struct UsingDirectiveSyntax {
    string namespace_name;
    int line = 1;
    int column = 1;
};

struct CompilationUnitSyntax {
    fs::path file;
    vector<UsingDirectiveSyntax> using_directives;
    vector<unique_ptr<ClassDeclarationSyntax>> classes;
};

class Parser {
public:
    Parser(fs::path file, vector<Token> tokens, DiagnosticBag& diagnostics)
        : file_(std::move(file)), tokens_(std::move(tokens)), diagnostics_(diagnostics) {}

    CompilationUnitSyntax parse() {
        CompilationUnitSyntax unit;
        unit.file = file_;

        while (match(TokenKind::Using)) {
            const Token start = previous();
            auto parts = parse_qualified_name();
            consume(TokenKind::Semicolon, "Expected ';' after using directive");
            unit.using_directives.push_back(UsingDirectiveSyntax{join_qualified(parts), start.line, start.column});
        }

        while (!check(TokenKind::EndOfFile)) {
            if (match(TokenKind::Namespace)) {
                const auto namespace_name = join_qualified(parse_qualified_name());
                consume(TokenKind::OpenBrace, "Expected '{' after namespace declaration");
                while (!check(TokenKind::CloseBrace) && !check(TokenKind::EndOfFile)) {
                    unit.classes.push_back(parse_class_declaration(namespace_name));
                }
                consume(TokenKind::CloseBrace, "Expected '}' after namespace block");
                continue;
            }

            unit.classes.push_back(parse_class_declaration(""));
        }

        return unit;
    }

private:
    const Token& current() const {
        return tokens_[index_];
    }

    const Token& peek(std::size_t offset) const {
        const std::size_t position = std::min(index_ + offset, tokens_.size() - 1);
        return tokens_[position];
    }

    bool check(TokenKind kind) const {
        return current().kind == kind;
    }

    bool match(TokenKind kind) {
        if (check(kind)) {
            ++index_;
            return true;
        }
        return false;
    }

    const Token& advance() {
        if (!check(TokenKind::EndOfFile)) {
            ++index_;
        }
        return previous();
    }

    const Token& previous() const {
        return tokens_[index_ - 1];
    }

    const Token& consume(TokenKind kind, const string& message) {
        if (check(kind)) {
            return advance();
        }
        diagnostics_.add(file_, current().line, current().column, message);
        if (!check(TokenKind::EndOfFile)) {
            advance();
            return previous();
        }
        return current();
    }

    vector<ModifierKind> parse_modifiers() {
        vector<ModifierKind> modifiers;
        bool keep_parsing = true;
        while (keep_parsing) {
            keep_parsing = false;
            if (match(TokenKind::Public)) {
                modifiers.push_back(ModifierKind::Public);
                keep_parsing = true;
            } else if (match(TokenKind::Private)) {
                modifiers.push_back(ModifierKind::Private);
                keep_parsing = true;
            } else if (match(TokenKind::Protected)) {
                modifiers.push_back(ModifierKind::Protected);
                keep_parsing = true;
            } else if (match(TokenKind::Internal)) {
                modifiers.push_back(ModifierKind::Internal);
                keep_parsing = true;
            } else if (match(TokenKind::Static)) {
                modifiers.push_back(ModifierKind::Static);
                keep_parsing = true;
            }
        }
        return modifiers;
    }

    vector<string> parse_qualified_name() {
        vector<string> parts;
        if (check(TokenKind::Identifier) || is_builtin_type_token(current().kind)) {
            parts.push_back(advance().text);
            while (match(TokenKind::Dot)) {
                const Token name = consume(TokenKind::Identifier, "Expected identifier after '.'");
                parts.push_back(name.text);
            }
        } else {
            diagnostics_.add(file_, current().line, current().column, "Expected qualified name");
        }
        return parts;
    }

    unique_ptr<ClassDeclarationSyntax> parse_class_declaration(const string& namespace_name) {
        auto syntax = std::make_unique<ClassDeclarationSyntax>();
        syntax->modifiers = parse_modifiers();
        const Token class_token = consume(TokenKind::Class, "Expected 'class' declaration");
        const Token name = consume(TokenKind::Identifier, "Expected class name");
        syntax->namespace_name = namespace_name;
        syntax->name = name.text;
        syntax->line = class_token.line;
        syntax->column = class_token.column;
        consume(TokenKind::OpenBrace, "Expected '{' after class declaration");
        while (!check(TokenKind::CloseBrace) && !check(TokenKind::EndOfFile)) {
            syntax->members.push_back(parse_member_declaration(syntax->name));
        }
        consume(TokenKind::CloseBrace, "Expected '}' after class body");
        return syntax;
    }

    unique_ptr<MemberSyntax> parse_member_declaration(const string& class_name) {
        const auto modifiers = parse_modifiers();
        if (check(TokenKind::Identifier) && current().text == class_name && peek(1).kind == TokenKind::OpenParen) {
            auto constructor = std::make_unique<ConstructorDeclarationSyntax>();
            constructor->modifiers = modifiers;
            constructor->line = current().line;
            constructor->column = current().column;
            constructor->name = advance().text;
            consume(TokenKind::OpenParen, "Expected '(' after constructor name");
            constructor->parameters = parse_parameter_list();
            consume(TokenKind::CloseParen, "Expected ')' after constructor parameters");
            constructor->body = parse_block_statement();
            return constructor;
        }

        TypeSyntax type = parse_type_syntax();
        const Token name = consume(TokenKind::Identifier, "Expected member name");
        if (match(TokenKind::OpenParen)) {
            auto method = std::make_unique<MethodDeclarationSyntax>();
            method->modifiers = modifiers;
            method->line = name.line;
            method->column = name.column;
            method->return_type = std::move(type);
            method->name = name.text;
            method->parameters = parse_parameter_list();
            consume(TokenKind::CloseParen, "Expected ')' after parameter list");
            method->body = parse_block_statement();
            return method;
        }

        auto field = std::make_unique<FieldDeclarationSyntax>();
        field->modifiers = modifiers;
        field->line = name.line;
        field->column = name.column;
        field->type = std::move(type);
        field->name = name.text;
        consume(TokenKind::Semicolon, "Expected ';' after field declaration");
        return field;
    }

    TypeSyntax parse_type_syntax() {
        TypeSyntax type;
        type.line = current().line;
        type.column = current().column;

        if (check(TokenKind::Void)) {
            type.name_parts.push_back(advance().text);
        } else if (check(TokenKind::Identifier) || is_builtin_type_token(current().kind)) {
            type.name_parts = parse_qualified_name();
        } else {
            diagnostics_.add(file_, current().line, current().column, "Expected type name");
            type.name_parts.push_back("error");
        }

        while (match(TokenKind::OpenBracket)) {
            consume(TokenKind::CloseBracket, "Expected ']' after '[' in array type");
            ++type.array_rank;
        }
        return type;
    }

    vector<ParameterSyntax> parse_parameter_list() {
        vector<ParameterSyntax> parameters;
        if (check(TokenKind::CloseParen)) {
            return parameters;
        }

        do {
            TypeSyntax type = parse_type_syntax();
            const Token name = consume(TokenKind::Identifier, "Expected parameter name");
            parameters.push_back(ParameterSyntax{std::move(type), name.text, name.line, name.column});
        } while (match(TokenKind::Comma));

        return parameters;
    }

    unique_ptr<BlockStatementSyntax> parse_block_statement() {
        const Token brace = consume(TokenKind::OpenBrace, "Expected '{' to start block");
        auto block = std::make_unique<BlockStatementSyntax>();
        block->line = brace.line;
        block->column = brace.column;
        while (!check(TokenKind::CloseBrace) && !check(TokenKind::EndOfFile)) {
            block->statements.push_back(parse_statement());
        }
        consume(TokenKind::CloseBrace, "Expected '}' after block");
        return block;
    }

    bool looks_like_variable_declaration() const {
        std::size_t cursor = index_;
        if (!(tokens_[cursor].kind == TokenKind::Identifier || is_builtin_type_token(tokens_[cursor].kind))) {
            return false;
        }

        ++cursor;
        while (tokens_[cursor].kind == TokenKind::Dot && tokens_[cursor + 1].kind == TokenKind::Identifier) {
            cursor += 2;
        }

        while (tokens_[cursor].kind == TokenKind::OpenBracket && tokens_[cursor + 1].kind == TokenKind::CloseBracket) {
            cursor += 2;
        }

        if (tokens_[cursor].kind != TokenKind::Identifier) {
            return false;
        }

        const TokenKind following = tokens_[cursor + 1].kind;
        return following == TokenKind::Semicolon || following == TokenKind::Equals;
    }

    unique_ptr<StatementSyntax> parse_statement() {
        if (check(TokenKind::OpenBrace)) {
            return parse_block_statement();
        }
        if (match(TokenKind::If)) {
            return parse_if_statement(previous());
        }
        if (match(TokenKind::While)) {
            return parse_while_statement(previous());
        }
        if (match(TokenKind::Return)) {
            return parse_return_statement(previous());
        }
        if (looks_like_variable_declaration()) {
            return parse_variable_declaration();
        }
        return parse_expression_statement();
    }

    unique_ptr<StatementSyntax> parse_if_statement(const Token& token) {
        consume(TokenKind::OpenParen, "Expected '(' after 'if'");
        auto condition = parse_expression();
        consume(TokenKind::CloseParen, "Expected ')' after if condition");
        auto statement = std::make_unique<IfStatementSyntax>();
        statement->line = token.line;
        statement->column = token.column;
        statement->condition = std::move(condition);
        statement->then_statement = parse_statement();
        if (match(TokenKind::Else)) {
            statement->else_statement = parse_statement();
        }
        return statement;
    }

    unique_ptr<StatementSyntax> parse_while_statement(const Token& token) {
        consume(TokenKind::OpenParen, "Expected '(' after 'while'");
        auto statement = std::make_unique<WhileStatementSyntax>();
        statement->line = token.line;
        statement->column = token.column;
        statement->condition = parse_expression();
        consume(TokenKind::CloseParen, "Expected ')' after while condition");
        statement->body = parse_statement();
        return statement;
    }

    unique_ptr<StatementSyntax> parse_return_statement(const Token& token) {
        auto statement = std::make_unique<ReturnStatementSyntax>();
        statement->line = token.line;
        statement->column = token.column;
        if (!check(TokenKind::Semicolon)) {
            statement->expression = parse_expression();
        }
        consume(TokenKind::Semicolon, "Expected ';' after return statement");
        return statement;
    }

    unique_ptr<StatementSyntax> parse_variable_declaration() {
        auto statement = std::make_unique<VariableDeclarationStatementSyntax>();
        statement->line = current().line;
        statement->column = current().column;
        statement->type = parse_type_syntax();
        const Token name = consume(TokenKind::Identifier, "Expected variable name");
        statement->name = name.text;
        if (match(TokenKind::Equals)) {
            statement->initializer = parse_expression();
        }
        consume(TokenKind::Semicolon, "Expected ';' after variable declaration");
        return statement;
    }

    unique_ptr<StatementSyntax> parse_expression_statement() {
        auto statement = std::make_unique<ExpressionStatementSyntax>();
        statement->line = current().line;
        statement->column = current().column;
        statement->expression = parse_expression();
        consume(TokenKind::Semicolon, "Expected ';' after expression");
        return statement;
    }

    unique_ptr<ExpressionSyntax> parse_expression() {
        return parse_assignment_expression();
    }

    unique_ptr<ExpressionSyntax> parse_assignment_expression() {
        auto left = parse_logical_or_expression();
        if (match(TokenKind::Equals)) {
            const Token token = previous();
            auto assignment = std::make_unique<AssignmentExpressionSyntax>();
            assignment->line = token.line;
            assignment->column = token.column;
            assignment->target = std::move(left);
            assignment->expression = parse_assignment_expression();
            return assignment;
        }
        return left;
    }

    unique_ptr<ExpressionSyntax> parse_logical_or_expression() {
        auto expression = parse_logical_and_expression();
        while (match(TokenKind::PipePipe)) {
            const Token token = previous();
            auto binary = std::make_unique<BinaryExpressionSyntax>();
            binary->line = token.line;
            binary->column = token.column;
            binary->left = std::move(expression);
            binary->op = token.kind;
            binary->right = parse_logical_and_expression();
            expression = std::move(binary);
        }
        return expression;
    }

    unique_ptr<ExpressionSyntax> parse_logical_and_expression() {
        auto expression = parse_equality_expression();
        while (match(TokenKind::AmpAmp)) {
            const Token token = previous();
            auto binary = std::make_unique<BinaryExpressionSyntax>();
            binary->line = token.line;
            binary->column = token.column;
            binary->left = std::move(expression);
            binary->op = token.kind;
            binary->right = parse_equality_expression();
            expression = std::move(binary);
        }
        return expression;
    }

    unique_ptr<ExpressionSyntax> parse_equality_expression() {
        auto expression = parse_relational_expression();
        while (match(TokenKind::EqualsEquals) || match(TokenKind::BangEquals)) {
            const Token token = previous();
            auto binary = std::make_unique<BinaryExpressionSyntax>();
            binary->line = token.line;
            binary->column = token.column;
            binary->left = std::move(expression);
            binary->op = token.kind;
            binary->right = parse_relational_expression();
            expression = std::move(binary);
        }
        return expression;
    }

    unique_ptr<ExpressionSyntax> parse_relational_expression() {
        auto expression = parse_additive_expression();
        while (match(TokenKind::Less) || match(TokenKind::LessEquals) ||
               match(TokenKind::Greater) || match(TokenKind::GreaterEquals)) {
            const Token token = previous();
            auto binary = std::make_unique<BinaryExpressionSyntax>();
            binary->line = token.line;
            binary->column = token.column;
            binary->left = std::move(expression);
            binary->op = token.kind;
            binary->right = parse_additive_expression();
            expression = std::move(binary);
        }
        return expression;
    }

    unique_ptr<ExpressionSyntax> parse_additive_expression() {
        auto expression = parse_multiplicative_expression();
        while (match(TokenKind::Plus) || match(TokenKind::Minus)) {
            const Token token = previous();
            auto binary = std::make_unique<BinaryExpressionSyntax>();
            binary->line = token.line;
            binary->column = token.column;
            binary->left = std::move(expression);
            binary->op = token.kind;
            binary->right = parse_multiplicative_expression();
            expression = std::move(binary);
        }
        return expression;
    }

    unique_ptr<ExpressionSyntax> parse_multiplicative_expression() {
        auto expression = parse_unary_expression();
        while (match(TokenKind::Star) || match(TokenKind::Slash)) {
            const Token token = previous();
            auto binary = std::make_unique<BinaryExpressionSyntax>();
            binary->line = token.line;
            binary->column = token.column;
            binary->left = std::move(expression);
            binary->op = token.kind;
            binary->right = parse_unary_expression();
            expression = std::move(binary);
        }
        return expression;
    }

    unique_ptr<ExpressionSyntax> parse_unary_expression() {
        if (match(TokenKind::Bang) || match(TokenKind::Minus) || match(TokenKind::Plus)) {
            const Token token = previous();
            auto unary = std::make_unique<UnaryExpressionSyntax>();
            unary->line = token.line;
            unary->column = token.column;
            unary->op = token.kind;
            unary->operand = parse_unary_expression();
            return unary;
        }
        return parse_postfix_expression();
    }

    unique_ptr<ExpressionSyntax> parse_postfix_expression() {
        auto expression = parse_primary_expression();
        while (true) {
            if (match(TokenKind::Dot)) {
                const Token member = consume(TokenKind::Identifier, "Expected member name after '.'");
                auto access = std::make_unique<MemberAccessExpressionSyntax>();
                access->line = member.line;
                access->column = member.column;
                access->target = std::move(expression);
                access->member_name = member.text;
                expression = std::move(access);
                continue;
            }

            if (match(TokenKind::OpenParen)) {
                auto invocation = std::make_unique<InvocationExpressionSyntax>();
                invocation->line = previous().line;
                invocation->column = previous().column;
                invocation->callee = std::move(expression);
                if (!check(TokenKind::CloseParen)) {
                    do {
                        invocation->arguments.push_back(parse_expression());
                    } while (match(TokenKind::Comma));
                }
                consume(TokenKind::CloseParen, "Expected ')' after arguments");
                expression = std::move(invocation);
                continue;
            }

            break;
        }
        return expression;
    }

    unique_ptr<ExpressionSyntax> parse_primary_expression() {
        const Token token = current();
        if (match(TokenKind::Number)) {
            auto literal = std::make_unique<LiteralExpressionSyntax>();
            literal->line = token.line;
            literal->column = token.column;
            literal->value = static_cast<int64_t>(std::stoll(token.text));
            return literal;
        }
        if (match(TokenKind::StringLiteral)) {
            auto literal = std::make_unique<LiteralExpressionSyntax>();
            literal->line = token.line;
            literal->column = token.column;
            literal->value = token.text;
            return literal;
        }
        if (match(TokenKind::True)) {
            auto literal = std::make_unique<LiteralExpressionSyntax>();
            literal->line = token.line;
            literal->column = token.column;
            literal->value = true;
            return literal;
        }
        if (match(TokenKind::False)) {
            auto literal = std::make_unique<LiteralExpressionSyntax>();
            literal->line = token.line;
            literal->column = token.column;
            literal->value = false;
            return literal;
        }
        if (match(TokenKind::Null)) {
            auto literal = std::make_unique<LiteralExpressionSyntax>();
            literal->line = token.line;
            literal->column = token.column;
            literal->value = nullptr;
            return literal;
        }
        if (match(TokenKind::This)) {
            auto expression = std::make_unique<ThisExpressionSyntax>();
            expression->line = token.line;
            expression->column = token.column;
            return expression;
        }
        if (match(TokenKind::Identifier)) {
            auto expression = std::make_unique<NameExpressionSyntax>();
            expression->line = token.line;
            expression->column = token.column;
            expression->name = token.text;
            return expression;
        }
        if (match(TokenKind::New)) {
            auto expression = std::make_unique<ObjectCreationExpressionSyntax>();
            expression->line = token.line;
            expression->column = token.column;
            expression->type = parse_type_syntax();
            consume(TokenKind::OpenParen, "Expected '(' after type name");
            if (!check(TokenKind::CloseParen)) {
                do {
                    expression->arguments.push_back(parse_expression());
                } while (match(TokenKind::Comma));
            }
            consume(TokenKind::CloseParen, "Expected ')' after constructor arguments");
            return expression;
        }
        if (match(TokenKind::OpenParen)) {
            auto expression = parse_expression();
            consume(TokenKind::CloseParen, "Expected ')' after expression");
            return expression;
        }

        diagnostics_.add(file_, current().line, current().column, "Expected expression");
        auto fallback = std::make_unique<LiteralExpressionSyntax>();
        fallback->line = current().line;
        fallback->column = current().column;
        fallback->value = nullptr;
        advance();
        return fallback;
    }

    static bool is_builtin_type_token(TokenKind kind) {
        return kind == TokenKind::Int || kind == TokenKind::StringKeyword || kind == TokenKind::Bool;
    }

    fs::path file_;
    vector<Token> tokens_;
    DiagnosticBag& diagnostics_;
    std::size_t index_ = 0;
};

enum class TypeKind {
    Void,
    Int,
    Bool,
    String,
    Null,
    Array,
    Class,
    Error,
};

enum class Accessibility {
    Private,
    Protected,
    Internal,
    Public,
};

struct ClassSymbol;

struct TypeSymbol {
    TypeKind kind = TypeKind::Error;
    string display_name = "error";
    const TypeSymbol* element_type = nullptr;
    const ClassSymbol* class_symbol = nullptr;
};

struct VariableSymbol {
    string name;
    const TypeSymbol* type = nullptr;
    int id = 0;
};

struct ParameterSymbol {
    string name;
    const TypeSymbol* type = nullptr;
    int index = 0;
};

struct FieldSymbol {
    string name;
    const TypeSymbol* type = nullptr;
    bool is_static = false;
    int slot = 0;
    const ClassSymbol* owner = nullptr;
    Accessibility accessibility = Accessibility::Private;
};

struct MethodSymbol {
    string name;
    const TypeSymbol* return_type = nullptr;
    vector<ParameterSymbol> parameters;
    bool is_static = false;
    bool is_builtin = false;
    int slot = 0;
    const ClassSymbol* owner = nullptr;
    Accessibility accessibility = Accessibility::Private;
    const MethodDeclarationSyntax* syntax = nullptr;
};

struct ConstructorSymbol {
    vector<ParameterSymbol> parameters;
    int slot = 0;
    const ClassSymbol* owner = nullptr;
    Accessibility accessibility = Accessibility::Private;
    const ConstructorDeclarationSyntax* syntax = nullptr;
};

struct ClassSymbol {
    string namespace_name;
    string name;
    string full_name;
    fs::path source_file;
    bool is_builtin = false;
    vector<string> using_namespaces;
    const ClassDeclarationSyntax* syntax = nullptr;
    vector<std::unique_ptr<FieldSymbol>> fields;
    vector<std::unique_ptr<MethodSymbol>> methods;
    vector<std::unique_ptr<ConstructorSymbol>> constructors;
};

struct BoundStatement;
struct BoundExpression;

enum class BoundExpressionKind {
    Literal,
    Local,
    Parameter,
    ThisReference,
    Field,
    ArrayLength,
    Assignment,
    Unary,
    Binary,
    Call,
    NewObject,
};

enum class BoundStatementKind {
    Block,
    VariableDeclaration,
    Expression,
    If,
    While,
    Return,
};

struct BoundExpression {
    virtual ~BoundExpression() = default;
    BoundExpressionKind kind = BoundExpressionKind::Literal;
    const TypeSymbol* type = nullptr;
    int line = 1;
    int column = 1;
};

struct BoundLiteralExpression final : BoundExpression {
    std::variant<std::nullptr_t, int64_t, bool, string> value;
};

struct BoundLocalExpression final : BoundExpression {
    const VariableSymbol* variable = nullptr;
};

struct BoundParameterExpression final : BoundExpression {
    const ParameterSymbol* parameter = nullptr;
};

struct BoundThisExpression final : BoundExpression {};

struct BoundFieldExpression final : BoundExpression {
    std::unique_ptr<BoundExpression> receiver;
    const FieldSymbol* field = nullptr;
};

struct BoundArrayLengthExpression final : BoundExpression {
    std::unique_ptr<BoundExpression> array_expression;
};

struct BoundAssignmentExpression final : BoundExpression {
    std::unique_ptr<BoundExpression> target;
    std::unique_ptr<BoundExpression> expression;
};

struct BoundUnaryExpression final : BoundExpression {
    TokenKind op = TokenKind::Plus;
    std::unique_ptr<BoundExpression> operand;
};

struct BoundBinaryExpression final : BoundExpression {
    std::unique_ptr<BoundExpression> left;
    TokenKind op = TokenKind::Plus;
    std::unique_ptr<BoundExpression> right;
};

struct BoundCallExpression final : BoundExpression {
    const MethodSymbol* method = nullptr;
    std::unique_ptr<BoundExpression> receiver;
    vector<std::unique_ptr<BoundExpression>> arguments;
};

struct BoundNewExpression final : BoundExpression {
    const ClassSymbol* class_symbol = nullptr;
    const ConstructorSymbol* constructor = nullptr;
    vector<std::unique_ptr<BoundExpression>> arguments;
};

struct BoundStatement {
    virtual ~BoundStatement() = default;
    BoundStatementKind kind = BoundStatementKind::Expression;
    int line = 1;
    int column = 1;
};

struct BoundBlockStatement final : BoundStatement {
    vector<std::unique_ptr<BoundStatement>> statements;
};

struct BoundVariableDeclarationStatement final : BoundStatement {
    const VariableSymbol* variable = nullptr;
    std::unique_ptr<BoundExpression> initializer;
};

struct BoundExpressionStatement final : BoundStatement {
    std::unique_ptr<BoundExpression> expression;
};

struct BoundIfStatement final : BoundStatement {
    std::unique_ptr<BoundExpression> condition;
    std::unique_ptr<BoundStatement> then_statement;
    std::unique_ptr<BoundStatement> else_statement;
};

struct BoundWhileStatement final : BoundStatement {
    std::unique_ptr<BoundExpression> condition;
    std::unique_ptr<BoundStatement> body;
};

struct BoundReturnStatement final : BoundStatement {
    std::unique_ptr<BoundExpression> expression;
};

struct BoundMethodBody {
    const MethodSymbol* method = nullptr;
    vector<std::unique_ptr<VariableSymbol>> locals;
    std::unique_ptr<BoundBlockStatement> body;
};

struct BoundConstructorBody {
    const ConstructorSymbol* constructor = nullptr;
    vector<std::unique_ptr<VariableSymbol>> locals;
    std::unique_ptr<BoundBlockStatement> body;
};

struct SemanticModel {
    std::vector<std::unique_ptr<TypeSymbol>> owned_types;
    std::unordered_map<string, TypeSymbol*> array_types;
    TypeSymbol void_type{TypeKind::Void, "void", nullptr, nullptr};
    TypeSymbol int_type{TypeKind::Int, "int", nullptr, nullptr};
    TypeSymbol bool_type{TypeKind::Bool, "bool", nullptr, nullptr};
    TypeSymbol string_type{TypeKind::String, "string", nullptr, nullptr};
    TypeSymbol null_type{TypeKind::Null, "null", nullptr, nullptr};
    TypeSymbol error_type{TypeKind::Error, "error", nullptr, nullptr};
    std::vector<std::unique_ptr<ClassSymbol>> classes;
    std::unordered_map<string, ClassSymbol*> classes_by_full_name;
    std::unordered_set<string> namespaces;
    ClassSymbol* console_class = nullptr;
    MethodSymbol* console_writeline_string = nullptr;
    MethodSymbol* console_writeline_int = nullptr;
    MethodSymbol* console_writeline_bool = nullptr;
    int next_variable_id = 1;

    const TypeSymbol* get_array_type(const TypeSymbol* element_type) {
        const string key = element_type->display_name + "[]";
        const auto found = array_types.find(key);
        if (found != array_types.end()) {
            return found->second;
        }
        auto type = std::make_unique<TypeSymbol>();
        type->kind = TypeKind::Array;
        type->display_name = key;
        type->element_type = element_type;
        auto* raw = type.get();
        owned_types.push_back(std::move(type));
        array_types[key] = raw;
        return raw;
    }
};

struct BoundProgram {
    SemanticModel semantic_model;
    vector<CompilationUnitSyntax> units;
    std::unordered_map<const MethodSymbol*, std::unique_ptr<BoundMethodBody>> methods;
    std::unordered_map<const ConstructorSymbol*, std::unique_ptr<BoundConstructorBody>> constructors;
    const MethodSymbol* entry_point = nullptr;
};

bool has_modifier(const vector<ModifierKind>& modifiers, ModifierKind kind) {
    return std::find(modifiers.begin(), modifiers.end(), kind) != modifiers.end();
}

Accessibility accessibility_from_modifiers(const vector<ModifierKind>& modifiers) {
    if (has_modifier(modifiers, ModifierKind::Public)) {
        return Accessibility::Public;
    }
    if (has_modifier(modifiers, ModifierKind::Protected)) {
        return Accessibility::Protected;
    }
    if (has_modifier(modifiers, ModifierKind::Internal)) {
        return Accessibility::Internal;
    }
    return Accessibility::Private;
}

bool is_accessible_from(Accessibility accessibility, const ClassSymbol& owner, const ClassSymbol& current_class) {
    switch (accessibility) {
        case Accessibility::Public:
            return true;
        case Accessibility::Internal:
            return true;
        case Accessibility::Private:
        case Accessibility::Protected:
            return &owner == &current_class;
    }
    return false;
}

string accessibility_text(Accessibility accessibility) {
    switch (accessibility) {
        case Accessibility::Public:
            return "public";
        case Accessibility::Protected:
            return "protected";
        case Accessibility::Internal:
            return "internal";
        case Accessibility::Private:
            return "private";
    }
    return "private";
}

bool is_type_assignable(const TypeSymbol* destination, const TypeSymbol* source) {
    if (destination == nullptr || source == nullptr) {
        return false;
    }
    if (destination == source) {
        return true;
    }
    if (destination->kind == source->kind) {
        switch (destination->kind) {
            case TypeKind::Void:
            case TypeKind::Int:
            case TypeKind::Bool:
            case TypeKind::String:
                return true;
            case TypeKind::Class:
                return destination->class_symbol == source->class_symbol ||
                       destination->display_name == source->display_name;
            case TypeKind::Array:
                return destination->element_type != nullptr && source->element_type != nullptr &&
                       is_type_assignable(destination->element_type, source->element_type);
            case TypeKind::Null:
                return true;
            case TypeKind::Error:
                return true;
        }
    }
    if (source->kind == TypeKind::Null &&
        (destination->kind == TypeKind::Class || destination->kind == TypeKind::String || destination->kind == TypeKind::Array)) {
        return true;
    }
    return false;
}

const TypeSymbol* resolve_type_in_context(SemanticModel& model,
                                          DiagnosticBag& diagnostics,
                                          const fs::path& file,
                                          const TypeSyntax& type,
                                          const string& current_namespace,
                                          const vector<string>& using_namespaces) {
    const string name = join_qualified(type.name_parts);
    const TypeSymbol* base = nullptr;

    if (type.array_rank > 0 && name == "void") {
        diagnostics.add(file, type.line, type.column, "void cannot be used as an array element type");
        return &model.error_type;
    }

    if (name == "void") {
        base = &model.void_type;
    } else if (name == "int") {
        base = &model.int_type;
    } else if (name == "bool") {
        base = &model.bool_type;
    } else if (name == "string") {
        base = &model.string_type;
    } else {
        vector<string> candidates;
        if (name.find('.') != string::npos) {
            candidates.push_back(name);
        } else {
            if (!current_namespace.empty()) {
                candidates.push_back(current_namespace + "." + name);
            }
            for (const auto& using_namespace : using_namespaces) {
                candidates.push_back(using_namespace + "." + name);
            }
            candidates.push_back(name);
        }

        for (const auto& candidate : candidates) {
            const auto found = model.classes_by_full_name.find(candidate);
            if (found != model.classes_by_full_name.end()) {
                auto type_symbol = std::make_unique<TypeSymbol>();
                type_symbol->kind = TypeKind::Class;
                type_symbol->display_name = found->second->full_name;
                type_symbol->class_symbol = found->second;
                base = type_symbol.get();
                model.owned_types.push_back(std::move(type_symbol));
                break;
            }
        }
    }

    if (base == nullptr) {
        diagnostics.add(file, type.line, type.column, "Unknown type '" + name + "'");
        return &model.error_type;
    }

    const TypeSymbol* resolved = base;
    for (int rank = 0; rank < type.array_rank; ++rank) {
        resolved = model.get_array_type(resolved);
    }
    return resolved;
}

class SemanticBuilder {
public:
    SemanticBuilder(vector<CompilationUnitSyntax> units, DiagnosticBag& diagnostics)
        : units_(std::move(units)), diagnostics_(diagnostics) {}

    std::unique_ptr<BoundProgram> build() {
        auto program = std::make_unique<BoundProgram>();
        program->units = std::move(units_);
        install_builtins(program->semantic_model);
        declare_classes(program->semantic_model, program->units);
        validate_using_directives(program->semantic_model, program->units);
        declare_members(program->semantic_model);
        bind_bodies(*program);
        return program;
    }

private:
    void install_builtins(SemanticModel& model) {
        model.namespaces.insert("System");
        auto console = std::make_unique<ClassSymbol>();
        console->namespace_name = "System";
        console->name = "Console";
        console->full_name = "System.Console";
        console->is_builtin = true;
        auto console_type = console.get();

        auto create_builtin = [&](const string& name, const TypeSymbol* parameter_type) -> MethodSymbol* {
            auto method = std::make_unique<MethodSymbol>();
            method->name = name;
            method->return_type = &model.void_type;
            method->parameters.push_back(ParameterSymbol{"value", parameter_type, 0});
            method->is_static = true;
            method->is_builtin = true;
            method->accessibility = Accessibility::Public;
            method->owner = console_type;
            method->slot = static_cast<int>(console_type->methods.size());
            auto* raw = method.get();
            console_type->methods.push_back(std::move(method));
            return raw;
        };

        model.console_writeline_string = create_builtin("WriteLine", &model.string_type);
        model.console_writeline_int = create_builtin("WriteLine", &model.int_type);
        model.console_writeline_bool = create_builtin("WriteLine", &model.bool_type);
        model.console_class = console_type;
        model.classes_by_full_name[console->full_name] = console_type;
        model.classes.push_back(std::move(console));
    }

    void declare_classes(SemanticModel& model, const vector<CompilationUnitSyntax>& units) {
        for (const auto& unit : units) {
            vector<string> using_namespaces;
            for (const auto& using_directive : unit.using_directives) {
                using_namespaces.push_back(using_directive.namespace_name);
            }

            for (const auto& class_syntax : unit.classes) {
                const string full_name = class_syntax->namespace_name.empty()
                                             ? class_syntax->name
                                             : class_syntax->namespace_name + "." + class_syntax->name;
                if (model.classes_by_full_name.count(full_name) > 0) {
                    diagnostics_.add(unit.file, class_syntax->line, class_syntax->column,
                                     "Duplicate class declaration for '" + full_name + "'");
                    continue;
                }

                auto symbol = std::make_unique<ClassSymbol>();
                symbol->namespace_name = class_syntax->namespace_name;
                symbol->name = class_syntax->name;
                symbol->full_name = full_name;
                symbol->source_file = unit.file;
                symbol->syntax = class_syntax.get();
                symbol->using_namespaces = using_namespaces;
                auto* raw = symbol.get();
                model.classes_by_full_name[full_name] = raw;
                model.classes.push_back(std::move(symbol));

                if (!class_syntax->namespace_name.empty()) {
                    vector<string> parts;
                    std::stringstream stream(class_syntax->namespace_name);
                    string segment;
                    while (std::getline(stream, segment, '.')) {
                        parts.push_back(segment);
                        model.namespaces.insert(join_qualified(parts));
                    }
                }
            }
        }
    }

    void validate_using_directives(const SemanticModel& model, const vector<CompilationUnitSyntax>& units) {
        for (const auto& unit : units) {
            for (const auto& directive : unit.using_directives) {
                if (model.namespaces.count(directive.namespace_name) == 0 &&
                    model.classes_by_full_name.count(directive.namespace_name) == 0) {
                    diagnostics_.add(unit.file, directive.line, directive.column,
                                     "Unresolved using directive '" + directive.namespace_name + "'");
                }
            }
        }
    }

    void declare_members(SemanticModel& model) {
        for (const auto& class_holder : model.classes) {
            ClassSymbol* klass = class_holder.get();
            if (klass->is_builtin || klass->syntax == nullptr) {
                continue;
            }

            std::unordered_set<string> field_names;
            std::unordered_set<string> method_signatures;
            std::unordered_set<string> ctor_signatures;

            for (const auto& member : klass->syntax->members) {
                if (const auto* field = dynamic_cast<FieldDeclarationSyntax*>(member.get())) {
                    if (!field_names.insert(field->name).second) {
                        diagnostics_.add(klass->source_file, field->line, field->column,
                                         "Duplicate field '" + field->name + "' in class '" + klass->full_name + "'");
                        continue;
                    }
                    auto symbol = std::make_unique<FieldSymbol>();
                    symbol->name = field->name;
                    symbol->type = resolve_type_in_context(model,
                                                           diagnostics_,
                                                           klass->source_file,
                                                           field->type,
                                                           klass->namespace_name,
                                                           klass->using_namespaces);
                    symbol->is_static = has_modifier(field->modifiers, ModifierKind::Static);
                    symbol->accessibility = accessibility_from_modifiers(field->modifiers);
                    symbol->slot = static_cast<int>(klass->fields.size());
                    symbol->owner = klass;
                    klass->fields.push_back(std::move(symbol));
                    continue;
                }

                if (const auto* method = dynamic_cast<MethodDeclarationSyntax*>(member.get())) {
                    auto symbol = std::make_unique<MethodSymbol>();
                    symbol->name = method->name;
                    symbol->return_type = resolve_type_in_context(model,
                                                                  diagnostics_,
                                                                  klass->source_file,
                                                                  method->return_type,
                                                                  klass->namespace_name,
                                                                  klass->using_namespaces);
                    symbol->is_static = has_modifier(method->modifiers, ModifierKind::Static);
                    symbol->accessibility = accessibility_from_modifiers(method->modifiers);
                    symbol->owner = klass;
                    symbol->syntax = method;
                    for (std::size_t index = 0; index < method->parameters.size(); ++index) {
                        const auto& parameter = method->parameters[index];
                        symbol->parameters.push_back(ParameterSymbol{
                            parameter.name,
                            resolve_type_in_context(model,
                                                    diagnostics_,
                                                    klass->source_file,
                                                    parameter.type,
                                                    klass->namespace_name,
                                                    klass->using_namespaces),
                            static_cast<int>(index)});
                    }
                    const string signature =
                        method->name + "#" + std::to_string(method->parameters.size()) + "#" + (symbol->is_static ? "S" : "I");
                    if (!method_signatures.insert(signature).second) {
                        diagnostics_.add(find_file_for_class(klass), method->line, method->column,
                                         "Duplicate method '" + method->name + "' in class '" + klass->full_name + "'");
                        continue;
                    }
                    symbol->slot = static_cast<int>(klass->methods.size());
                    klass->methods.push_back(std::move(symbol));
                    continue;
                }

                if (const auto* constructor = dynamic_cast<ConstructorDeclarationSyntax*>(member.get())) {
                    auto symbol = std::make_unique<ConstructorSymbol>();
                    symbol->owner = klass;
                    symbol->syntax = constructor;
                    symbol->accessibility = accessibility_from_modifiers(constructor->modifiers);
                    for (std::size_t index = 0; index < constructor->parameters.size(); ++index) {
                        const auto& parameter = constructor->parameters[index];
                        symbol->parameters.push_back(ParameterSymbol{
                            parameter.name,
                            resolve_type_in_context(model,
                                                    diagnostics_,
                                                    klass->source_file,
                                                    parameter.type,
                                                    klass->namespace_name,
                                                    klass->using_namespaces),
                            static_cast<int>(index)});
                    }
                    const string signature = "ctor#" + std::to_string(constructor->parameters.size());
                    if (!ctor_signatures.insert(signature).second) {
                        diagnostics_.add(find_file_for_class(klass), constructor->line, constructor->column,
                                         "Duplicate constructor in class '" + klass->full_name + "'");
                        continue;
                    }
                    symbol->slot = static_cast<int>(klass->constructors.size());
                    klass->constructors.push_back(std::move(symbol));
                }
            }
        }
    }

    struct EntityResolution {
        enum class Kind {
            Error,
            Namespace,
            Type,
            Value,
            MethodGroup,
        };

        Kind kind = Kind::Error;
        string namespace_name;
        const ClassSymbol* type_symbol = nullptr;
        std::unique_ptr<BoundExpression> value;
        vector<const MethodSymbol*> methods;
        std::unique_ptr<BoundExpression> receiver;
    };

    class Binder {
    public:
        Binder(BoundProgram& program, ClassSymbol& current_class, DiagnosticBag& diagnostics)
            : program_(program), current_class_(current_class), diagnostics_(diagnostics) {}

        std::unique_ptr<BoundMethodBody> bind_method(const MethodSymbol& method) {
            current_method_ = &method;
            current_constructor_ = nullptr;
            parameter_lookup_.clear();
            locals_.clear();
            scopes_.clear();
            push_scope();
            for (const auto& parameter : method.parameters) {
                parameter_lookup_[parameter.name] = &parameter;
            }
            auto body = std::make_unique<BoundMethodBody>();
            body->method = &method;
            body->body = bind_block(*method.syntax->body);
            body->locals = std::move(locals_);
            pop_scope();
            return body;
        }

        std::unique_ptr<BoundConstructorBody> bind_constructor(const ConstructorSymbol& constructor) {
            current_method_ = nullptr;
            current_constructor_ = &constructor;
            parameter_lookup_.clear();
            locals_.clear();
            scopes_.clear();
            push_scope();
            for (const auto& parameter : constructor.parameters) {
                parameter_lookup_[parameter.name] = &parameter;
            }
            auto body = std::make_unique<BoundConstructorBody>();
            body->constructor = &constructor;
            body->body = bind_block(*constructor.syntax->body);
            body->locals = std::move(locals_);
            pop_scope();
            return body;
        }

    private:
        const TypeSymbol* current_return_type() const {
            if (current_method_ != nullptr) {
                return current_method_->return_type;
            }
            return &program_.semantic_model.void_type;
        }

        std::unique_ptr<BoundExpression> make_this_expression(int line, int column) {
            auto this_expression = std::make_unique<BoundThisExpression>();
            this_expression->kind = BoundExpressionKind::ThisReference;
            this_expression->line = line;
            this_expression->column = column;
            auto this_type = std::make_unique<TypeSymbol>();
            this_type->kind = TypeKind::Class;
            this_type->display_name = current_class_.full_name;
            this_type->class_symbol = &current_class_;
            this_expression->type = this_type.get();
            program_.semantic_model.owned_types.push_back(std::move(this_type));
            return this_expression;
        }

        std::unique_ptr<BoundExpression> make_field_expression(std::unique_ptr<BoundExpression> receiver,
                                                               const FieldSymbol* field,
                                                               int line,
                                                               int column) {
            auto field_expression = std::make_unique<BoundFieldExpression>();
            field_expression->kind = BoundExpressionKind::Field;
            field_expression->type = field->type;
            field_expression->line = line;
            field_expression->column = column;
            field_expression->receiver = std::move(receiver);
            field_expression->field = field;
            return field_expression;
        }

        bool is_accessible(const FieldSymbol& field) const {
            return field.owner != nullptr && is_accessible_from(field.accessibility, *field.owner, current_class_);
        }

        bool is_accessible(const MethodSymbol& method) const {
            return method.owner != nullptr && is_accessible_from(method.accessibility, *method.owner, current_class_);
        }

        bool is_accessible(const ConstructorSymbol& constructor) const {
            return constructor.owner != nullptr && is_accessible_from(constructor.accessibility, *constructor.owner, current_class_);
        }

        const FieldSymbol* select_field(const ClassSymbol& klass,
                                        const string& name,
                                        bool require_static,
                                        bool* found_inaccessible = nullptr) const {
            for (const auto& field : klass.fields) {
                if (field->name != name || field->is_static != require_static) {
                    continue;
                }
                if (is_accessible(*field)) {
                    return field.get();
                }
                if (found_inaccessible != nullptr) {
                    *found_inaccessible = true;
                }
            }
            return nullptr;
        }

        vector<const MethodSymbol*> select_methods(const ClassSymbol& klass,
                                                   const string& name,
                                                   bool require_static,
                                                   bool* found_inaccessible = nullptr) const {
            vector<const MethodSymbol*> methods;
            for (const auto& method : klass.methods) {
                if (method->name != name || method->is_static != require_static) {
                    continue;
                }
                if (is_accessible(*method)) {
                    methods.push_back(method.get());
                } else if (found_inaccessible != nullptr) {
                    *found_inaccessible = true;
                }
            }
            return methods;
        }

        void report_inaccessible(const string& member_name,
                                 Accessibility accessibility,
                                 const ClassSymbol& owner,
                                 int line,
                                 int column) {
            diagnostics_.add(find_file_for_class(&current_class_),
                             line,
                             column,
                             "'" + owner.full_name + "." + member_name + "' is inaccessible due to its " +
                                 accessibility_text(accessibility) + " protection level");
        }

        void push_scope() {
            scopes_.push_back({});
        }

        void pop_scope() {
            scopes_.pop_back();
        }

        const VariableSymbol* declare_local(const string& name, const TypeSymbol* type) {
            auto local = std::make_unique<VariableSymbol>();
            local->name = name;
            local->type = type;
            local->id = program_.semantic_model.next_variable_id++;
            auto* raw = local.get();
            locals_.push_back(std::move(local));
            scopes_.back()[name] = raw;
            return raw;
        }

        const VariableSymbol* lookup_local(const string& name) const {
            for (auto scope = scopes_.rbegin(); scope != scopes_.rend(); ++scope) {
                const auto found = scope->find(name);
                if (found != scope->end()) {
                    return found->second;
                }
            }
            return nullptr;
        }

        std::unique_ptr<BoundBlockStatement> bind_block(const BlockStatementSyntax& block) {
            auto statement = std::make_unique<BoundBlockStatement>();
            statement->kind = BoundStatementKind::Block;
            statement->line = block.line;
            statement->column = block.column;
            push_scope();
            for (const auto& child : block.statements) {
                statement->statements.push_back(bind_statement(*child));
            }
            pop_scope();
            return statement;
        }

        std::unique_ptr<BoundStatement> bind_statement(const StatementSyntax& statement) {
            if (const auto* block = dynamic_cast<const BlockStatementSyntax*>(&statement)) {
                return bind_block(*block);
            }
            if (const auto* variable = dynamic_cast<const VariableDeclarationStatementSyntax*>(&statement)) {
                auto bound = std::make_unique<BoundVariableDeclarationStatement>();
                bound->kind = BoundStatementKind::VariableDeclaration;
                bound->line = variable->line;
                bound->column = variable->column;
                const TypeSymbol* type = resolve_type(variable->type);
                if (scopes_.back().count(variable->name) > 0) {
                    diagnostics_.add(find_file_for_class(&current_class_), variable->line, variable->column,
                                     "Local variable '" + variable->name + "' is already declared in this scope");
                }
                bound->variable = declare_local(variable->name, type);
                if (variable->initializer != nullptr) {
                    bound->initializer = bind_expression(*variable->initializer);
                    if (!is_type_assignable(type, bound->initializer->type)) {
                        diagnostics_.add(find_file_for_class(&current_class_), variable->line, variable->column,
                                         "Cannot assign expression of type '" + bound->initializer->type->display_name +
                                             "' to variable of type '" + type->display_name + "'");
                    }
                }
                return bound;
            }
            if (const auto* expression = dynamic_cast<const ExpressionStatementSyntax*>(&statement)) {
                auto bound = std::make_unique<BoundExpressionStatement>();
                bound->kind = BoundStatementKind::Expression;
                bound->line = expression->line;
                bound->column = expression->column;
                bound->expression = bind_expression(*expression->expression);
                return bound;
            }
            if (const auto* if_statement = dynamic_cast<const IfStatementSyntax*>(&statement)) {
                auto bound = std::make_unique<BoundIfStatement>();
                bound->kind = BoundStatementKind::If;
                bound->line = if_statement->line;
                bound->column = if_statement->column;
                bound->condition = bind_expression(*if_statement->condition);
                if (bound->condition->type != &program_.semantic_model.bool_type) {
                    diagnostics_.add(find_file_for_class(&current_class_), if_statement->line, if_statement->column,
                                     "If condition must be of type 'bool'");
                }
                bound->then_statement = bind_statement(*if_statement->then_statement);
                if (if_statement->else_statement != nullptr) {
                    bound->else_statement = bind_statement(*if_statement->else_statement);
                }
                return bound;
            }
            if (const auto* while_statement = dynamic_cast<const WhileStatementSyntax*>(&statement)) {
                auto bound = std::make_unique<BoundWhileStatement>();
                bound->kind = BoundStatementKind::While;
                bound->line = while_statement->line;
                bound->column = while_statement->column;
                bound->condition = bind_expression(*while_statement->condition);
                if (bound->condition->type != &program_.semantic_model.bool_type) {
                    diagnostics_.add(find_file_for_class(&current_class_), while_statement->line, while_statement->column,
                                     "While condition must be of type 'bool'");
                }
                bound->body = bind_statement(*while_statement->body);
                return bound;
            }
            if (const auto* return_statement = dynamic_cast<const ReturnStatementSyntax*>(&statement)) {
                auto bound = std::make_unique<BoundReturnStatement>();
                bound->kind = BoundStatementKind::Return;
                bound->line = return_statement->line;
                bound->column = return_statement->column;
                if (return_statement->expression != nullptr) {
                    bound->expression = bind_expression(*return_statement->expression);
                }
                const TypeSymbol* expected = current_return_type();
                if (expected == &program_.semantic_model.void_type) {
                    if (bound->expression != nullptr) {
                        diagnostics_.add(find_file_for_class(&current_class_), return_statement->line, return_statement->column,
                                         "Void methods cannot return a value");
                    }
                } else if (bound->expression == nullptr) {
                    diagnostics_.add(find_file_for_class(&current_class_), return_statement->line, return_statement->column,
                                     "Non-void methods must return a value");
                } else if (!is_type_assignable(expected, bound->expression->type)) {
                    diagnostics_.add(find_file_for_class(&current_class_), return_statement->line, return_statement->column,
                                     "Return expression type '" + bound->expression->type->display_name +
                                         "' is not assignable to '" + expected->display_name + "'");
                }
                return bound;
            }

            auto fallback = std::make_unique<BoundExpressionStatement>();
            fallback->kind = BoundStatementKind::Expression;
            fallback->line = statement.line;
            fallback->column = statement.column;
            auto literal = std::make_unique<BoundLiteralExpression>();
            literal->kind = BoundExpressionKind::Literal;
            literal->type = &program_.semantic_model.null_type;
            literal->line = statement.line;
            literal->column = statement.column;
            literal->value = nullptr;
            fallback->expression = std::move(literal);
            return fallback;
        }

        std::unique_ptr<BoundExpression> bind_expression(const ExpressionSyntax& expression) {
            if (const auto* literal = dynamic_cast<const LiteralExpressionSyntax*>(&expression)) {
                auto bound = std::make_unique<BoundLiteralExpression>();
                bound->kind = BoundExpressionKind::Literal;
                bound->line = expression.line;
                bound->column = expression.column;
                bound->value = literal->value;
                if (std::holds_alternative<int64_t>(literal->value)) {
                    bound->type = &program_.semantic_model.int_type;
                } else if (std::holds_alternative<bool>(literal->value)) {
                    bound->type = &program_.semantic_model.bool_type;
                } else if (std::holds_alternative<string>(literal->value)) {
                    bound->type = &program_.semantic_model.string_type;
                } else {
                    bound->type = &program_.semantic_model.null_type;
                }
                return bound;
            }

            if (dynamic_cast<const ThisExpressionSyntax*>(&expression) != nullptr) {
                return make_this_expression(expression.line, expression.column);
            }

            if (const auto* assignment = dynamic_cast<const AssignmentExpressionSyntax*>(&expression)) {
                auto target = bind_assignable_expression(*assignment->target);
                auto value = bind_expression(*assignment->expression);
                auto bound = std::make_unique<BoundAssignmentExpression>();
                bound->kind = BoundExpressionKind::Assignment;
                bound->line = expression.line;
                bound->column = expression.column;
                if (!is_type_assignable(target->type, value->type)) {
                    diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                     "Cannot assign expression of type '" + value->type->display_name +
                                         "' to target of type '" + target->type->display_name + "'");
                }
                bound->type = target->type;
                bound->target = std::move(target);
                bound->expression = std::move(value);
                return bound;
            }

            if (const auto* unary = dynamic_cast<const UnaryExpressionSyntax*>(&expression)) {
                auto operand = bind_expression(*unary->operand);
                auto bound = std::make_unique<BoundUnaryExpression>();
                bound->kind = BoundExpressionKind::Unary;
                bound->line = expression.line;
                bound->column = expression.column;
                bound->op = unary->op;
                bound->operand = std::move(operand);
                if (unary->op == TokenKind::Bang) {
                    if (bound->operand->type != &program_.semantic_model.bool_type) {
                        diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                         "Operator '!' requires a bool operand");
                    }
                    bound->type = &program_.semantic_model.bool_type;
                } else {
                    if (bound->operand->type != &program_.semantic_model.int_type) {
                        diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                         "Unary '+' and '-' require int operands");
                    }
                    bound->type = &program_.semantic_model.int_type;
                }
                return bound;
            }

            if (const auto* binary = dynamic_cast<const BinaryExpressionSyntax*>(&expression)) {
                auto left = bind_expression(*binary->left);
                auto right = bind_expression(*binary->right);
                auto bound = std::make_unique<BoundBinaryExpression>();
                bound->kind = BoundExpressionKind::Binary;
                bound->line = expression.line;
                bound->column = expression.column;
                bound->left = std::move(left);
                bound->right = std::move(right);
                bound->op = binary->op;
                switch (binary->op) {
                    case TokenKind::Plus:
                    case TokenKind::Minus:
                    case TokenKind::Star:
                    case TokenKind::Slash:
                        if (bound->left->type != &program_.semantic_model.int_type ||
                            bound->right->type != &program_.semantic_model.int_type) {
                            diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                             "Arithmetic operators require int operands");
                        }
                        bound->type = &program_.semantic_model.int_type;
                        break;
                    case TokenKind::AmpAmp:
                    case TokenKind::PipePipe:
                        if (bound->left->type != &program_.semantic_model.bool_type ||
                            bound->right->type != &program_.semantic_model.bool_type) {
                            diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                             "Logical operators require bool operands");
                        }
                        bound->type = &program_.semantic_model.bool_type;
                        break;
                    case TokenKind::EqualsEquals:
                    case TokenKind::BangEquals:
                        if (!is_type_assignable(bound->left->type, bound->right->type) &&
                            !is_type_assignable(bound->right->type, bound->left->type)) {
                            diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                             "Equality operators require compatible operands");
                        }
                        bound->type = &program_.semantic_model.bool_type;
                        break;
                    case TokenKind::Less:
                    case TokenKind::LessEquals:
                    case TokenKind::Greater:
                    case TokenKind::GreaterEquals:
                        if (bound->left->type != &program_.semantic_model.int_type ||
                            bound->right->type != &program_.semantic_model.int_type) {
                            diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                             "Relational operators require int operands");
                        }
                        bound->type = &program_.semantic_model.bool_type;
                        break;
                    default:
                        bound->type = &program_.semantic_model.error_type;
                        break;
                }
                return bound;
            }

            if (const auto* invocation = dynamic_cast<const InvocationExpressionSyntax*>(&expression)) {
                return bind_invocation(*invocation);
            }

            if (const auto* creation = dynamic_cast<const ObjectCreationExpressionSyntax*>(&expression)) {
                return bind_object_creation(*creation);
            }

            return bind_value_expression(expression);
        }

        std::unique_ptr<BoundExpression> bind_value_expression(const ExpressionSyntax& expression) {
            EntityResolution entity = bind_entity(expression);
            if (entity.kind == EntityResolution::Kind::Value && entity.value != nullptr) {
                return std::move(entity.value);
            }
            if (entity.kind == EntityResolution::Kind::Error) {
                auto fallback = std::make_unique<BoundLiteralExpression>();
                fallback->kind = BoundExpressionKind::Literal;
                fallback->type = &program_.semantic_model.error_type;
                fallback->line = expression.line;
                fallback->column = expression.column;
                fallback->value = nullptr;
                return fallback;
            }

            diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                             "Expected a value expression");
            auto fallback = std::make_unique<BoundLiteralExpression>();
            fallback->kind = BoundExpressionKind::Literal;
            fallback->type = &program_.semantic_model.error_type;
            fallback->line = expression.line;
            fallback->column = expression.column;
            fallback->value = nullptr;
            return fallback;
        }

        std::unique_ptr<BoundExpression> bind_assignable_expression(const ExpressionSyntax& expression) {
            EntityResolution entity = bind_entity(expression);
            const bool assignable = entity.kind == EntityResolution::Kind::Value &&
                                    entity.value != nullptr &&
                                    (entity.value->kind == BoundExpressionKind::Local ||
                                     entity.value->kind == BoundExpressionKind::Parameter ||
                                     entity.value->kind == BoundExpressionKind::Field);
            if (!assignable) {
                diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                 "Expected an assignable value expression");
                auto fallback = std::make_unique<BoundLiteralExpression>();
                fallback->kind = BoundExpressionKind::Literal;
                fallback->type = &program_.semantic_model.error_type;
                fallback->line = expression.line;
                fallback->column = expression.column;
                fallback->value = nullptr;
                return fallback;
            }
            return std::move(entity.value);
        }

        std::unique_ptr<BoundExpression> bind_invocation(const InvocationExpressionSyntax& syntax) {
            EntityResolution entity = bind_entity(*syntax.callee);
            if (entity.kind == EntityResolution::Kind::Error) {
                auto fallback = std::make_unique<BoundLiteralExpression>();
                fallback->kind = BoundExpressionKind::Literal;
                fallback->type = &program_.semantic_model.error_type;
                fallback->line = syntax.line;
                fallback->column = syntax.column;
                fallback->value = nullptr;
                return fallback;
            }
            if (entity.kind != EntityResolution::Kind::MethodGroup) {
                diagnostics_.add(find_file_for_class(&current_class_), syntax.line, syntax.column,
                                 "Expression is not invocable");
                auto fallback = std::make_unique<BoundLiteralExpression>();
                fallback->kind = BoundExpressionKind::Literal;
                fallback->type = &program_.semantic_model.error_type;
                fallback->line = syntax.line;
                fallback->column = syntax.column;
                fallback->value = nullptr;
                return fallback;
            }

            vector<std::unique_ptr<BoundExpression>> arguments;
            vector<const TypeSymbol*> argument_types;
            bool has_error_argument = false;
            for (const auto& argument : syntax.arguments) {
                auto bound = bind_expression(*argument);
                if (bound->type == &program_.semantic_model.error_type) {
                    has_error_argument = true;
                }
                argument_types.push_back(bound->type);
                arguments.push_back(std::move(bound));
            }

            if (has_error_argument) {
                auto fallback = std::make_unique<BoundLiteralExpression>();
                fallback->kind = BoundExpressionKind::Literal;
                fallback->type = &program_.semantic_model.error_type;
                fallback->line = syntax.line;
                fallback->column = syntax.column;
                fallback->value = nullptr;
                return fallback;
            }

            const MethodSymbol* selected = nullptr;
            for (const auto* candidate : entity.methods) {
                if (candidate->parameters.size() != arguments.size()) {
                    continue;
                }
                bool compatible = true;
                for (std::size_t index = 0; index < arguments.size(); ++index) {
                    if (!is_type_assignable(candidate->parameters[index].type, argument_types[index])) {
                        compatible = false;
                        break;
                    }
                }
                if (compatible) {
                    selected = candidate;
                    break;
                }
            }

            if (selected == nullptr) {
                diagnostics_.add(find_file_for_class(&current_class_), syntax.line, syntax.column,
                                 "No overload of '" + render_callee_name(*syntax.callee) + "' matches the provided arguments");
                auto fallback = std::make_unique<BoundLiteralExpression>();
                fallback->kind = BoundExpressionKind::Literal;
                fallback->type = &program_.semantic_model.error_type;
                fallback->line = syntax.line;
                fallback->column = syntax.column;
                fallback->value = nullptr;
                return fallback;
            }

            auto call = std::make_unique<BoundCallExpression>();
            call->kind = BoundExpressionKind::Call;
            call->type = selected->return_type;
            call->line = syntax.line;
            call->column = syntax.column;
            call->method = selected;
            call->receiver = std::move(entity.receiver);
            call->arguments = std::move(arguments);
            return call;
        }

        std::unique_ptr<BoundExpression> bind_object_creation(const ObjectCreationExpressionSyntax& syntax) {
            const TypeSymbol* type = resolve_type(syntax.type);
            if (type->kind != TypeKind::Class || type->class_symbol == nullptr) {
                diagnostics_.add(find_file_for_class(&current_class_), syntax.line, syntax.column,
                                 "The 'new' operator requires a class type");
                auto fallback = std::make_unique<BoundLiteralExpression>();
                fallback->kind = BoundExpressionKind::Literal;
                fallback->type = &program_.semantic_model.error_type;
                fallback->line = syntax.line;
                fallback->column = syntax.column;
                fallback->value = nullptr;
                return fallback;
            }

            vector<std::unique_ptr<BoundExpression>> arguments;
            vector<const TypeSymbol*> argument_types;
            for (const auto& argument : syntax.arguments) {
                auto bound = bind_expression(*argument);
                argument_types.push_back(bound->type);
                arguments.push_back(std::move(bound));
            }

            const ConstructorSymbol* selected = nullptr;
            const ConstructorSymbol* inaccessible_match = nullptr;
            for (const auto& constructor : type->class_symbol->constructors) {
                if (constructor->parameters.size() != syntax.arguments.size()) {
                    continue;
                }
                bool compatible = true;
                for (std::size_t index = 0; index < arguments.size(); ++index) {
                    if (!is_type_assignable(constructor->parameters[index].type, argument_types[index])) {
                        compatible = false;
                    }
                }
                if (!compatible) {
                    continue;
                }
                if (is_accessible(*constructor)) {
                    selected = constructor.get();
                    break;
                }
                inaccessible_match = constructor.get();
            }

            if (selected == nullptr && !type->class_symbol->constructors.empty() && inaccessible_match != nullptr) {
                report_inaccessible(type->class_symbol->name, inaccessible_match->accessibility, *inaccessible_match->owner, syntax.line, syntax.column);
            } else if (selected == nullptr && !type->class_symbol->constructors.empty()) {
                diagnostics_.add(find_file_for_class(&current_class_), syntax.line, syntax.column,
                                 "No constructor matches the provided arguments for '" + type->display_name + "'");
            }

            auto bound = std::make_unique<BoundNewExpression>();
            bound->kind = BoundExpressionKind::NewObject;
            bound->type = type;
            bound->line = syntax.line;
            bound->column = syntax.column;
            bound->class_symbol = type->class_symbol;
            bound->constructor = selected;
            bound->arguments = std::move(arguments);
            return bound;
        }

        EntityResolution bind_entity(const ExpressionSyntax& expression) {
            if (const auto* name = dynamic_cast<const NameExpressionSyntax*>(&expression)) {
                if (const auto* local = lookup_local(name->name)) {
                    EntityResolution result;
                    result.kind = EntityResolution::Kind::Value;
                    auto value = std::make_unique<BoundLocalExpression>();
                    value->kind = BoundExpressionKind::Local;
                    value->type = local->type;
                    value->line = expression.line;
                    value->column = expression.column;
                    value->variable = local;
                    result.value = std::move(value);
                    return result;
                }

                const auto parameter = parameter_lookup_.find(name->name);
                if (parameter != parameter_lookup_.end()) {
                    EntityResolution result;
                    result.kind = EntityResolution::Kind::Value;
                    auto value = std::make_unique<BoundParameterExpression>();
                    value->kind = BoundExpressionKind::Parameter;
                    value->type = parameter->second->type;
                    value->line = expression.line;
                    value->column = expression.column;
                    value->parameter = parameter->second;
                    result.value = std::move(value);
                    return result;
                }

                if (!is_current_static_context()) {
                    if (const auto* field = select_field(current_class_, name->name, false)) {
                        EntityResolution result;
                        result.kind = EntityResolution::Kind::Value;
                        result.value = make_field_expression(make_this_expression(expression.line, expression.column),
                                                             field,
                                                             expression.line,
                                                             expression.column);
                        return result;
                    }
                }

                if (const auto* field = select_field(current_class_, name->name, true)) {
                    EntityResolution result;
                    result.kind = EntityResolution::Kind::Value;
                    result.value = make_field_expression(nullptr, field, expression.line, expression.column);
                    return result;
                }

                if (!is_current_static_context()) {
                    bool found_inaccessible = false;
                    auto methods = select_methods(current_class_, name->name, false, &found_inaccessible);
                    if (!methods.empty()) {
                        EntityResolution result;
                        result.kind = EntityResolution::Kind::MethodGroup;
                        result.methods = std::move(methods);
                        result.receiver = make_this_expression(expression.line, expression.column);
                        return result;
                    }
                    if (found_inaccessible) {
                        for (const auto& method : current_class_.methods) {
                            if (method->name == name->name && !method->is_static) {
                                report_inaccessible(name->name, method->accessibility, *method->owner, expression.line, expression.column);
                                return {};
                            }
                        }
                    }
                }

                {
                    bool found_inaccessible = false;
                    auto methods = select_methods(current_class_, name->name, true, &found_inaccessible);
                    if (!methods.empty()) {
                        EntityResolution result;
                        result.kind = EntityResolution::Kind::MethodGroup;
                        result.methods = std::move(methods);
                        return result;
                    }
                    if (found_inaccessible) {
                        for (const auto& method : current_class_.methods) {
                            if (method->name == name->name && method->is_static) {
                                report_inaccessible(name->name, method->accessibility, *method->owner, expression.line, expression.column);
                                return {};
                            }
                        }
                    }
                }

                if (const ClassSymbol* type = resolve_class(name->name)) {
                    EntityResolution result;
                    result.kind = EntityResolution::Kind::Type;
                    result.type_symbol = type;
                    return result;
                }

                if (is_namespace(name->name)) {
                    EntityResolution result;
                    result.kind = EntityResolution::Kind::Namespace;
                    result.namespace_name = name->name;
                    return result;
                }

                diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                 "Unknown identifier '" + name->name + "'");
                return {};
            }

            if (dynamic_cast<const ThisExpressionSyntax*>(&expression) != nullptr) {
                EntityResolution result;
                if (is_current_static_context()) {
                    diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                     "'this' cannot be used in a static context");
                    return result;
                }
                result.kind = EntityResolution::Kind::Value;
                result.value = make_this_expression(expression.line, expression.column);
                return result;
            }

            if (const auto* member = dynamic_cast<const MemberAccessExpressionSyntax*>(&expression)) {
                EntityResolution base = bind_entity(*member->target);
                if (base.kind == EntityResolution::Kind::Namespace) {
                    const string candidate = base.namespace_name + "." + member->member_name;
                    if (is_namespace(candidate)) {
                        EntityResolution result;
                        result.kind = EntityResolution::Kind::Namespace;
                        result.namespace_name = candidate;
                        return result;
                    }
                    const auto class_found = program_.semantic_model.classes_by_full_name.find(candidate);
                    if (class_found != program_.semantic_model.classes_by_full_name.end()) {
                        EntityResolution result;
                        result.kind = EntityResolution::Kind::Type;
                        result.type_symbol = class_found->second;
                        return result;
                    }
                    diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                     "Unknown member '" + member->member_name + "' on namespace '" + base.namespace_name + "'");
                    return {};
                }

                if (base.kind == EntityResolution::Kind::Type) {
                    bool found_inaccessible = false;
                    if (const auto* field = select_field(*base.type_symbol, member->member_name, true, &found_inaccessible)) {
                        EntityResolution result;
                        result.kind = EntityResolution::Kind::Value;
                        result.type_symbol = base.type_symbol;
                        result.value = make_field_expression(nullptr, field, expression.line, expression.column);
                        return result;
                    }
                    EntityResolution result;
                    result.kind = EntityResolution::Kind::MethodGroup;
                    result.type_symbol = base.type_symbol;
                    result.methods = select_methods(*base.type_symbol, member->member_name, true, &found_inaccessible);
                    if (!result.methods.empty()) {
                        return result;
                    }
                    if (found_inaccessible) {
                        for (const auto& field_candidate : base.type_symbol->fields) {
                            if (field_candidate->is_static && field_candidate->name == member->member_name) {
                                report_inaccessible(member->member_name,
                                                    field_candidate->accessibility,
                                                    *field_candidate->owner,
                                                    expression.line,
                                                    expression.column);
                                return {};
                            }
                        }
                        for (const auto& method_candidate : base.type_symbol->methods) {
                            if (method_candidate->is_static && method_candidate->name == member->member_name) {
                                report_inaccessible(member->member_name,
                                                    method_candidate->accessibility,
                                                    *method_candidate->owner,
                                                    expression.line,
                                                    expression.column);
                                return {};
                            }
                        }
                    }
                    {
                        diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                         "Unknown static member '" + member->member_name + "' on type '" +
                                             base.type_symbol->full_name + "'");
                    }
                    return {};
                }

                if (base.kind == EntityResolution::Kind::Value) {
                    if (base.value->type != nullptr && base.value->type->kind == TypeKind::Array && member->member_name == "Length") {
                        auto length = std::make_unique<BoundArrayLengthExpression>();
                        length->kind = BoundExpressionKind::ArrayLength;
                        length->type = &program_.semantic_model.int_type;
                        length->line = expression.line;
                        length->column = expression.column;
                        length->array_expression = std::move(base.value);
                        EntityResolution result;
                        result.kind = EntityResolution::Kind::Value;
                        result.value = std::move(length);
                        return result;
                    }

                    if (base.value->type == nullptr || base.value->type->kind != TypeKind::Class ||
                        base.value->type->class_symbol == nullptr) {
                        diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                         "Type '" + base.value->type->display_name + "' does not contain members");
                        return {};
                    }

                    const ClassSymbol* klass = base.value->type->class_symbol;
                    bool found_inaccessible = false;
                    if (const auto* field = select_field(*klass, member->member_name, false, &found_inaccessible)) {
                        EntityResolution result;
                        result.kind = EntityResolution::Kind::Value;
                        result.value = make_field_expression(std::move(base.value), field, expression.line, expression.column);
                        return result;
                    }

                    EntityResolution result;
                    result.kind = EntityResolution::Kind::MethodGroup;
                    result.methods = select_methods(*klass, member->member_name, false, &found_inaccessible);
                    if (!result.methods.empty()) {
                        result.receiver = std::move(base.value);
                        return result;
                    }
                    if (found_inaccessible) {
                        for (const auto& field_candidate : klass->fields) {
                            if (!field_candidate->is_static && field_candidate->name == member->member_name) {
                                report_inaccessible(member->member_name,
                                                    field_candidate->accessibility,
                                                    *field_candidate->owner,
                                                    expression.line,
                                                    expression.column);
                                return {};
                            }
                        }
                        for (const auto& method_candidate : klass->methods) {
                            if (!method_candidate->is_static && method_candidate->name == member->member_name) {
                                report_inaccessible(member->member_name,
                                                    method_candidate->accessibility,
                                                    *method_candidate->owner,
                                                    expression.line,
                                                    expression.column);
                                return {};
                            }
                        }
                    }

                    diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                     "Unknown member '" + member->member_name + "' on type '" + klass->full_name + "'");
                    return {};
                }
            }

            auto value = bind_expression(expression);
            EntityResolution result;
            result.kind = EntityResolution::Kind::Value;
            result.value = std::move(value);
            return result;
        }

        bool is_current_static_context() const {
            return current_method_ != nullptr && current_method_->is_static;
        }

        bool is_namespace(const string& name) const {
            return program_.semantic_model.namespaces.count(name) > 0;
        }

        const ClassSymbol* resolve_class(const string& name) const {
            vector<string> candidates;
            if (name.find('.') != string::npos) {
                candidates.push_back(name);
            } else {
                if (!current_class_.namespace_name.empty()) {
                    candidates.push_back(current_class_.namespace_name + "." + name);
                }
                for (const auto& using_namespace : current_class_.using_namespaces) {
                    candidates.push_back(using_namespace + "." + name);
                }
                candidates.push_back(name);
            }
            for (const auto& candidate : candidates) {
                const auto found = program_.semantic_model.classes_by_full_name.find(candidate);
                if (found != program_.semantic_model.classes_by_full_name.end()) {
                    return found->second;
                }
            }
            return nullptr;
        }

        const TypeSymbol* resolve_type(const TypeSyntax& type) {
            return resolve_type_in_context(program_.semantic_model,
                                           diagnostics_,
                                           find_file_for_class(&current_class_),
                                           type,
                                           current_class_.namespace_name,
                                           current_class_.using_namespaces);
        }

        string render_callee_name(const ExpressionSyntax& expression) const {
            if (const auto* name = dynamic_cast<const NameExpressionSyntax*>(&expression)) {
                return name->name;
            }
            if (const auto* member = dynamic_cast<const MemberAccessExpressionSyntax*>(&expression)) {
                return member->member_name;
            }
            return "<expression>";
        }

        BoundProgram& program_;
        ClassSymbol& current_class_;
        DiagnosticBag& diagnostics_;
        const MethodSymbol* current_method_ = nullptr;
        const ConstructorSymbol* current_constructor_ = nullptr;
        std::unordered_map<string, const ParameterSymbol*> parameter_lookup_;
        vector<std::unique_ptr<VariableSymbol>> locals_;
        vector<std::unordered_map<string, const VariableSymbol*>> scopes_;
    };

    void bind_bodies(BoundProgram& program) {
        for (const auto& class_holder : program.semantic_model.classes) {
            ClassSymbol* klass = class_holder.get();
            if (klass->is_builtin) {
                continue;
            }

            Binder binder(program, *klass, diagnostics_);
            for (const auto& method : klass->methods) {
                program.methods[method.get()] = binder.bind_method(*method);
            }
            for (const auto& constructor : klass->constructors) {
                program.constructors[constructor.get()] = binder.bind_constructor(*constructor);
            }
        }
    }

    static fs::path find_file_for_class(const ClassSymbol* klass) {
        return klass != nullptr ? klass->source_file : fs::path{};
    }

    vector<CompilationUnitSyntax> units_;
    DiagnosticBag& diagnostics_;
};

bool locate_entry_point(BoundProgram& program, DiagnosticBag& diagnostics) {
    for (const auto& class_holder : program.semantic_model.classes) {
        for (const auto& method : class_holder->methods) {
            if (method->name != "Main" || !method->is_static) {
                continue;
            }
            if (method->return_type != &program.semantic_model.void_type &&
                method->return_type != &program.semantic_model.int_type) {
                continue;
            }
            if (method->parameters.empty()) {
                program.entry_point = method.get();
                return true;
            }
            if (method->parameters.size() == 1 &&
                method->parameters[0].type == program.semantic_model.get_array_type(&program.semantic_model.string_type)) {
                program.entry_point = method.get();
                return true;
            }
        }
    }

    diagnostics.add({}, 1, 1, "Entry point not found. Expected 'public static void Main(string[] args)' or 'public static void Main()'");
    return false;
}

string escape_c_string(const string& value) {
    std::ostringstream out;
    for (const char ch : value) {
        switch (ch) {
            case '\\':
                out << "\\\\";
                break;
            case '"':
                out << "\\\"";
                break;
            case '\n':
                out << "\\n";
                break;
            case '\t':
                out << "\\t";
                break;
            default:
                out << ch;
                break;
        }
    }
    return out.str();
}

string sanitize_c_name(string name) {
    for (char& ch : name) {
        if (!std::isalnum(static_cast<unsigned char>(ch))) {
            ch = '_';
        }
    }
    return name;
}

struct RuntimeArray;
struct RuntimeObject;

struct Value {
    using Storage = std::variant<std::nullptr_t, int64_t, bool, string, std::shared_ptr<RuntimeArray>, std::shared_ptr<RuntimeObject>>;
    Storage data = nullptr;
};

struct RuntimeArray {
    const TypeSymbol* element_type = nullptr;
    std::vector<Value> elements;
};

struct RuntimeObject {
    const ClassSymbol* class_symbol = nullptr;
    std::unordered_map<const FieldSymbol*, Value> fields;
};

Value default_value_for_type(const TypeSymbol* type) {
    switch (type->kind) {
        case TypeKind::Int:
            return Value{int64_t{0}};
        case TypeKind::Bool:
            return Value{false};
        case TypeKind::String:
        case TypeKind::Class:
        case TypeKind::Array:
        case TypeKind::Null:
            return Value{nullptr};
        case TypeKind::Void:
        case TypeKind::Error:
            return Value{nullptr};
    }
    return Value{nullptr};
}

bool values_equal(const Value& left, const Value& right) {
    if (left.data.index() != right.data.index()) {
        return std::holds_alternative<std::nullptr_t>(left.data) && std::holds_alternative<std::nullptr_t>(right.data);
    }
    if (std::holds_alternative<std::nullptr_t>(left.data)) {
        return true;
    }
    if (std::holds_alternative<int64_t>(left.data)) {
        return std::get<int64_t>(left.data) == std::get<int64_t>(right.data);
    }
    if (std::holds_alternative<bool>(left.data)) {
        return std::get<bool>(left.data) == std::get<bool>(right.data);
    }
    if (std::holds_alternative<string>(left.data)) {
        return std::get<string>(left.data) == std::get<string>(right.data);
    }
    if (std::holds_alternative<std::shared_ptr<RuntimeArray>>(left.data)) {
        return std::get<std::shared_ptr<RuntimeArray>>(left.data) == std::get<std::shared_ptr<RuntimeArray>>(right.data);
    }
    return std::get<std::shared_ptr<RuntimeObject>>(left.data) == std::get<std::shared_ptr<RuntimeObject>>(right.data);
}

class Interpreter {
public:
    explicit Interpreter(const BoundProgram& program) : program_(program) {
        for (const auto& class_holder : program_.semantic_model.classes) {
            for (const auto& field : class_holder->fields) {
                if (field->is_static) {
                    static_fields_[field.get()] = default_value_for_type(field->type);
                }
            }
        }
    }

    bool run(const vector<string>& args) {
        if (program_.entry_point == nullptr) {
            return false;
        }

        vector<Value> parameters;
        if (!program_.entry_point->parameters.empty()) {
            auto array = std::make_shared<RuntimeArray>();
            array->element_type = &program_.semantic_model.string_type;
            for (const auto& value : args) {
                array->elements.push_back(Value{value});
            }
            parameters.push_back(Value{array});
        }

        invoke_method(*program_.entry_point, nullptr, parameters);
        return true;
    }

private:
    struct Frame {
        std::unordered_map<const ParameterSymbol*, Value> parameters;
        std::unordered_map<const VariableSymbol*, Value> locals;
        std::shared_ptr<RuntimeObject> self;
    };

    struct ExecutionResult {
        bool has_return = false;
        Value value{};
    };

    Value invoke_method(const MethodSymbol& method,
                        std::shared_ptr<RuntimeObject> receiver,
                        const vector<Value>& arguments) {
        if (method.is_builtin) {
            if (method.owner == program_.semantic_model.console_class && method.name == "WriteLine") {
                if (arguments.empty()) {
                    std::cout << '\n';
                    return Value{nullptr};
                }
                const Value& value = arguments[0];
                if (std::holds_alternative<string>(value.data)) {
                    std::cout << std::get<string>(value.data) << '\n';
                } else if (std::holds_alternative<int64_t>(value.data)) {
                    std::cout << std::get<int64_t>(value.data) << '\n';
                } else if (std::holds_alternative<bool>(value.data)) {
                    std::cout << (std::get<bool>(value.data) ? "true" : "false") << '\n';
                } else {
                    std::cout << "null\n";
                }
                return Value{nullptr};
            }
        }

        Frame frame;
        frame.self = std::move(receiver);
        for (std::size_t index = 0; index < method.parameters.size() && index < arguments.size(); ++index) {
            frame.parameters[&method.parameters[index]] = arguments[index];
        }

        const auto found = program_.methods.find(&method);
        if (found == program_.methods.end()) {
            return default_value_for_type(method.return_type);
        }

        const ExecutionResult result = execute_statement(*found->second->body, frame);
        if (result.has_return) {
            return result.value;
        }
        return default_value_for_type(method.return_type);
    }

    void invoke_constructor(const ConstructorSymbol& constructor,
                            const std::shared_ptr<RuntimeObject>& receiver,
                            const vector<Value>& arguments) {
        Frame frame;
        frame.self = receiver;
        for (std::size_t index = 0; index < constructor.parameters.size() && index < arguments.size(); ++index) {
            frame.parameters[&constructor.parameters[index]] = arguments[index];
        }

        const auto found = program_.constructors.find(&constructor);
        if (found != program_.constructors.end()) {
            execute_statement(*found->second->body, frame);
        }
    }

    ExecutionResult execute_statement(const BoundStatement& statement, Frame& frame) {
        switch (statement.kind) {
            case BoundStatementKind::Block: {
                const auto& block = static_cast<const BoundBlockStatement&>(statement);
                for (const auto& child : block.statements) {
                    ExecutionResult result = execute_statement(*child, frame);
                    if (result.has_return) {
                        return result;
                    }
                }
                return {};
            }
            case BoundStatementKind::VariableDeclaration: {
                const auto& declaration = static_cast<const BoundVariableDeclarationStatement&>(statement);
                Value value = declaration.initializer != nullptr
                                  ? evaluate_expression(*declaration.initializer, frame)
                                  : default_value_for_type(declaration.variable->type);
                frame.locals[declaration.variable] = value;
                return {};
            }
            case BoundStatementKind::Expression: {
                const auto& expression = static_cast<const BoundExpressionStatement&>(statement);
                evaluate_expression(*expression.expression, frame);
                return {};
            }
            case BoundStatementKind::If: {
                const auto& if_statement = static_cast<const BoundIfStatement&>(statement);
                if (std::get<bool>(evaluate_expression(*if_statement.condition, frame).data)) {
                    return execute_statement(*if_statement.then_statement, frame);
                }
                if (if_statement.else_statement != nullptr) {
                    return execute_statement(*if_statement.else_statement, frame);
                }
                return {};
            }
            case BoundStatementKind::While: {
                const auto& while_statement = static_cast<const BoundWhileStatement&>(statement);
                while (std::get<bool>(evaluate_expression(*while_statement.condition, frame).data)) {
                    ExecutionResult result = execute_statement(*while_statement.body, frame);
                    if (result.has_return) {
                        return result;
                    }
                }
                return {};
            }
            case BoundStatementKind::Return: {
                const auto& return_statement = static_cast<const BoundReturnStatement&>(statement);
                if (return_statement.expression != nullptr) {
                    return ExecutionResult{true, evaluate_expression(*return_statement.expression, frame)};
                }
                return ExecutionResult{true, Value{nullptr}};
            }
        }
        return {};
    }

    Value& access_assignable(const BoundExpression& expression, Frame& frame) {
        if (expression.kind == BoundExpressionKind::Local) {
            const auto& local = static_cast<const BoundLocalExpression&>(expression);
            return frame.locals[local.variable];
        }
        if (expression.kind == BoundExpressionKind::Parameter) {
            const auto& parameter = static_cast<const BoundParameterExpression&>(expression);
            return frame.parameters[parameter.parameter];
        }
        if (expression.kind == BoundExpressionKind::Field) {
            const auto& field = static_cast<const BoundFieldExpression&>(expression);
            if (field.field->is_static) {
                return static_fields_[field.field];
            }
            auto receiver = std::get<std::shared_ptr<RuntimeObject>>(evaluate_expression(*field.receiver, frame).data);
            return receiver->fields[field.field];
        }
        throw std::runtime_error("Expression is not assignable");
    }

    Value evaluate_expression(const BoundExpression& expression, Frame& frame) {
        switch (expression.kind) {
            case BoundExpressionKind::Literal: {
                const auto& literal = static_cast<const BoundLiteralExpression&>(expression);
                if (std::holds_alternative<int64_t>(literal.value)) {
                    return Value{std::get<int64_t>(literal.value)};
                }
                if (std::holds_alternative<bool>(literal.value)) {
                    return Value{std::get<bool>(literal.value)};
                }
                if (std::holds_alternative<string>(literal.value)) {
                    return Value{std::get<string>(literal.value)};
                }
                return Value{nullptr};
            }
            case BoundExpressionKind::Local: {
                const auto& local = static_cast<const BoundLocalExpression&>(expression);
                return frame.locals[local.variable];
            }
            case BoundExpressionKind::Parameter: {
                const auto& parameter = static_cast<const BoundParameterExpression&>(expression);
                return frame.parameters[parameter.parameter];
            }
            case BoundExpressionKind::ThisReference:
                return Value{frame.self};
            case BoundExpressionKind::Field: {
                const auto& field = static_cast<const BoundFieldExpression&>(expression);
                if (field.field->is_static) {
                    return static_fields_[field.field];
                }
                auto receiver = std::get<std::shared_ptr<RuntimeObject>>(evaluate_expression(*field.receiver, frame).data);
                return receiver->fields[field.field];
            }
            case BoundExpressionKind::ArrayLength: {
                const auto& length = static_cast<const BoundArrayLengthExpression&>(expression);
                Value array_value = evaluate_expression(*length.array_expression, frame);
                if (std::holds_alternative<std::shared_ptr<RuntimeArray>>(array_value.data)) {
                    const auto& array = std::get<std::shared_ptr<RuntimeArray>>(array_value.data);
                    return Value{array != nullptr ? static_cast<int64_t>(array->elements.size()) : int64_t{0}};
                }
                return Value{int64_t{0}};
            }
            case BoundExpressionKind::Assignment: {
                const auto& assignment = static_cast<const BoundAssignmentExpression&>(expression);
                Value value = evaluate_expression(*assignment.expression, frame);
                access_assignable(*assignment.target, frame) = value;
                return value;
            }
            case BoundExpressionKind::Unary: {
                const auto& unary = static_cast<const BoundUnaryExpression&>(expression);
                Value operand = evaluate_expression(*unary.operand, frame);
                switch (unary.op) {
                    case TokenKind::Bang:
                        return Value{!std::get<bool>(operand.data)};
                    case TokenKind::Minus:
                        return Value{-std::get<int64_t>(operand.data)};
                    case TokenKind::Plus:
                        return Value{std::get<int64_t>(operand.data)};
                    default:
                        return Value{nullptr};
                }
            }
            case BoundExpressionKind::Binary: {
                const auto& binary = static_cast<const BoundBinaryExpression&>(expression);
                Value left = evaluate_expression(*binary.left, frame);
                Value right = evaluate_expression(*binary.right, frame);
                switch (binary.op) {
                    case TokenKind::Plus:
                        return Value{std::get<int64_t>(left.data) + std::get<int64_t>(right.data)};
                    case TokenKind::Minus:
                        return Value{std::get<int64_t>(left.data) - std::get<int64_t>(right.data)};
                    case TokenKind::Star:
                        return Value{std::get<int64_t>(left.data) * std::get<int64_t>(right.data)};
                    case TokenKind::Slash:
                        return Value{std::get<int64_t>(left.data) / std::get<int64_t>(right.data)};
                    case TokenKind::AmpAmp:
                        return Value{std::get<bool>(left.data) && std::get<bool>(right.data)};
                    case TokenKind::PipePipe:
                        return Value{std::get<bool>(left.data) || std::get<bool>(right.data)};
                    case TokenKind::EqualsEquals:
                        return Value{values_equal(left, right)};
                    case TokenKind::BangEquals:
                        return Value{!values_equal(left, right)};
                    case TokenKind::Less:
                        return Value{std::get<int64_t>(left.data) < std::get<int64_t>(right.data)};
                    case TokenKind::LessEquals:
                        return Value{std::get<int64_t>(left.data) <= std::get<int64_t>(right.data)};
                    case TokenKind::Greater:
                        return Value{std::get<int64_t>(left.data) > std::get<int64_t>(right.data)};
                    case TokenKind::GreaterEquals:
                        return Value{std::get<int64_t>(left.data) >= std::get<int64_t>(right.data)};
                    default:
                        return Value{nullptr};
                }
            }
            case BoundExpressionKind::Call: {
                const auto& call = static_cast<const BoundCallExpression&>(expression);
                vector<Value> arguments;
                for (const auto& argument : call.arguments) {
                    arguments.push_back(evaluate_expression(*argument, frame));
                }
                std::shared_ptr<RuntimeObject> receiver;
                if (call.receiver != nullptr) {
                    receiver = std::get<std::shared_ptr<RuntimeObject>>(evaluate_expression(*call.receiver, frame).data);
                }
                return invoke_method(*call.method, receiver, arguments);
            }
            case BoundExpressionKind::NewObject: {
                const auto& creation = static_cast<const BoundNewExpression&>(expression);
                auto instance = std::make_shared<RuntimeObject>();
                instance->class_symbol = creation.class_symbol;
                for (const auto& field : creation.class_symbol->fields) {
                    if (field->is_static) {
                        continue;
                    }
                    instance->fields[field.get()] = default_value_for_type(field->type);
                }
                vector<Value> arguments;
                for (const auto& argument : creation.arguments) {
                    arguments.push_back(evaluate_expression(*argument, frame));
                }
                if (creation.constructor != nullptr) {
                    invoke_constructor(*creation.constructor, instance, arguments);
                }
                return Value{instance};
            }
        }
        return Value{nullptr};
    }

    const BoundProgram& program_;
    std::unordered_map<const FieldSymbol*, Value> static_fields_;
};

string c_type_name(const TypeSymbol* type) {
    switch (type->kind) {
        case TypeKind::Void:
            return "void";
        case TypeKind::Int:
            return "int64_t";
        case TypeKind::Bool:
            return "bool";
        case TypeKind::String:
            return "const char*";
        case TypeKind::Array:
            return "HyStringArray";
        case TypeKind::Class:
            return sanitize_c_name(type->class_symbol->full_name) + "*";
        case TypeKind::Null:
            return "void*";
        case TypeKind::Error:
            return "void*";
    }
    return "void*";
}

class CEmitter {
public:
    explicit CEmitter(const BoundProgram& program) : program_(program) {}

    string emit_executable() {
        std::ostringstream out;
        emit_prelude(out);
        emit_classes(out);
        emit_method_prototypes(out);
        emit_constructors(out);
        emit_methods(out);
        emit_main(out);
        return out.str();
    }

    string emit_library() {
        std::ostringstream out;
        emit_prelude(out);
        emit_classes(out);
        emit_method_prototypes(out);
        emit_constructors(out);
        emit_methods(out);
        return out.str();
    }

private:
    string class_struct_name(const ClassSymbol& klass) const {
        return sanitize_c_name(klass.full_name);
    }

    string static_field_name(const FieldSymbol& field) const {
        return sanitize_c_name(field.owner->full_name + "_static_" + field.name);
    }

    string method_name(const MethodSymbol& method) const {
        return sanitize_c_name(method.owner->full_name + "_" + method.name + "_" + std::to_string(method.parameters.size()));
    }

    string constructor_name(const ConstructorSymbol& ctor) const {
        return sanitize_c_name(ctor.owner->full_name + "_ctor_" + std::to_string(ctor.parameters.size()));
    }

    string new_helper_name(const ClassSymbol& klass, int arity) const {
        return sanitize_c_name("hy_new_" + klass.full_name + "_" + std::to_string(arity));
    }

    void emit_prelude(std::ostringstream& out) {
        out << "#include <stdbool.h>\n";
        out << "#include <stdint.h>\n";
        out << "#include <stdio.h>\n";
        out << "#include <stdlib.h>\n";
        out << "#include <string.h>\n\n";
        out << "typedef struct {\n";
        out << "    int64_t length;\n";
        out << "    const char** items;\n";
        out << "} HyStringArray;\n\n";
        out << "static void** hy_managed_items = NULL;\n";
        out << "static size_t hy_managed_count = 0;\n";
        out << "static size_t hy_managed_capacity = 0;\n\n";
        out << "static void hy_runtime_shutdown(void) {\n";
        out << "    for (size_t index = 0; index < hy_managed_count; ++index) {\n";
        out << "        free(hy_managed_items[index]);\n";
        out << "    }\n";
        out << "    free(hy_managed_items);\n";
        out << "    hy_managed_items = NULL;\n";
        out << "    hy_managed_count = 0;\n";
        out << "    hy_managed_capacity = 0;\n";
        out << "}\n\n";
        out << "static void hy_track_allocation(void* memory) {\n";
        out << "    static bool hy_runtime_registered = false;\n";
        out << "    if (!hy_runtime_registered) {\n";
        out << "        atexit(hy_runtime_shutdown);\n";
        out << "        hy_runtime_registered = true;\n";
        out << "    }\n";
        out << "    if (hy_managed_count == hy_managed_capacity) {\n";
        out << "        size_t next_capacity = hy_managed_capacity == 0 ? 16 : hy_managed_capacity * 2;\n";
        out << "        void** next_items = (void**)realloc(hy_managed_items, next_capacity * sizeof(void*));\n";
        out << "        if (next_items == NULL) {\n";
        out << "            fprintf(stderr, \"Hylang allocation tracking failed\\n\");\n";
        out << "            free(memory);\n";
        out << "            exit(1);\n";
        out << "        }\n";
        out << "        hy_managed_items = next_items;\n";
        out << "        hy_managed_capacity = next_capacity;\n";
        out << "    }\n";
        out << "    hy_managed_items[hy_managed_count++] = memory;\n";
        out << "}\n\n";
        out << "static void* hy_alloc_managed(size_t size) {\n";
        out << "    void* memory = calloc(1, size);\n";
        out << "    if (memory == NULL) {\n";
        out << "        fprintf(stderr, \"Hylang allocation failed\\n\");\n";
        out << "        exit(1);\n";
        out << "    }\n";
        out << "    hy_track_allocation(memory);\n";
        out << "    return memory;\n";
        out << "}\n\n";
        out << "static void hy_console_writeline_string(const char* value) {\n";
        out << "    printf(\"%s\\n\", value == NULL ? \"null\" : value);\n";
        out << "}\n";
        out << "static void hy_console_writeline_int(int64_t value) {\n";
        out << "    printf(\"%lld\\n\", (long long)value);\n";
        out << "}\n";
        out << "static void hy_console_writeline_bool(bool value) {\n";
        out << "    printf(\"%s\\n\", value ? \"true\" : \"false\");\n";
        out << "}\n\n";
    }

    void emit_classes(std::ostringstream& out) {
        for (const auto& class_holder : program_.semantic_model.classes) {
            if (class_holder->is_builtin) {
                continue;
            }
            out << "typedef struct " << class_struct_name(*class_holder) << " {\n";
            for (const auto& field : class_holder->fields) {
                if (field->is_static) {
                    continue;
                }
                out << "    " << c_type_name(field->type) << " " << sanitize_c_name(field->name) << ";\n";
            }
            out << "} " << class_struct_name(*class_holder) << ";\n\n";
        }
        for (const auto& class_holder : program_.semantic_model.classes) {
            if (class_holder->is_builtin) {
                continue;
            }
            for (const auto& field : class_holder->fields) {
                if (!field->is_static) {
                    continue;
                }
                out << c_type_name(field->type) << " " << static_field_name(*field) << " = "
                    << default_expression(field->type) << ";\n";
            }
        }
        out << "\n";
    }

    void emit_method_prototypes(std::ostringstream& out) {
        for (const auto& class_holder : program_.semantic_model.classes) {
            if (class_holder->is_builtin) {
                continue;
            }
            for (const auto& ctor : class_holder->constructors) {
                out << "void " << constructor_name(*ctor) << "(" << class_struct_name(*class_holder) << "* self";
                for (const auto& parameter : ctor->parameters) {
                    out << ", " << c_type_name(parameter.type) << " " << sanitize_c_name(parameter.name);
                }
                out << ");\n";
                out << class_struct_name(*class_holder) << "* " << new_helper_name(*class_holder, static_cast<int>(ctor->parameters.size()))
                    << "(";
                for (std::size_t index = 0; index < ctor->parameters.size(); ++index) {
                    if (index > 0) {
                        out << ", ";
                    }
                    out << c_type_name(ctor->parameters[index].type) << " " << sanitize_c_name(ctor->parameters[index].name);
                }
                out << ");\n";
            }
            if (class_holder->constructors.empty()) {
                out << class_struct_name(*class_holder) << "* " << new_helper_name(*class_holder, 0) << "(void);\n";
            }
            for (const auto& method : class_holder->methods) {
                out << c_type_name(method->return_type) << " " << method_name(*method) << "(";
                bool wrote = false;
                if (!method->is_static) {
                    out << class_struct_name(*class_holder) << "* self";
                    wrote = true;
                }
                for (const auto& parameter : method->parameters) {
                    if (wrote) {
                        out << ", ";
                    }
                    out << c_type_name(parameter.type) << " " << sanitize_c_name(parameter.name);
                    wrote = true;
                }
                if (!wrote) {
                    out << "void";
                }
                out << ");\n";
            }
            out << "\n";
        }
    }

    void emit_constructors(std::ostringstream& out) {
        for (const auto& class_holder : program_.semantic_model.classes) {
            if (class_holder->is_builtin) {
                continue;
            }
            if (class_holder->constructors.empty()) {
                out << class_struct_name(*class_holder) << "* " << new_helper_name(*class_holder, 0) << "(void) {\n";
                out << "    " << class_struct_name(*class_holder) << "* self = (" << class_struct_name(*class_holder)
                    << "*)hy_alloc_managed(sizeof(" << class_struct_name(*class_holder) << "));\n";
                out << "    return self;\n";
                out << "}\n\n";
                continue;
            }

            for (const auto& ctor : class_holder->constructors) {
                out << "void " << constructor_name(*ctor) << "(" << class_struct_name(*class_holder) << "* self";
                for (const auto& parameter : ctor->parameters) {
                    out << ", " << c_type_name(parameter.type) << " " << sanitize_c_name(parameter.name);
                }
                out << ") {\n";
                emit_block(out, *program_.constructors.at(ctor.get())->body, 1);
                out << "}\n\n";

                out << class_struct_name(*class_holder) << "* " << new_helper_name(*class_holder, static_cast<int>(ctor->parameters.size()))
                    << "(";
                for (std::size_t index = 0; index < ctor->parameters.size(); ++index) {
                    if (index > 0) {
                        out << ", ";
                    }
                    out << c_type_name(ctor->parameters[index].type) << " " << sanitize_c_name(ctor->parameters[index].name);
                }
                if (ctor->parameters.empty()) {
                    out << "void";
                }
                out << ") {\n";
                out << "    " << class_struct_name(*class_holder) << "* self = (" << class_struct_name(*class_holder)
                    << "*)hy_alloc_managed(sizeof(" << class_struct_name(*class_holder) << "));\n";
                out << "    " << constructor_name(*ctor) << "(self";
                for (const auto& parameter : ctor->parameters) {
                    out << ", " << sanitize_c_name(parameter.name);
                }
                out << ");\n";
                out << "    return self;\n";
                out << "}\n\n";
            }
        }
    }

    void emit_methods(std::ostringstream& out) {
        for (const auto& class_holder : program_.semantic_model.classes) {
            if (class_holder->is_builtin) {
                continue;
            }
            for (const auto& method : class_holder->methods) {
                out << c_type_name(method->return_type) << " " << method_name(*method) << "(";
                bool wrote = false;
                if (!method->is_static) {
                    out << class_struct_name(*class_holder) << "* self";
                    wrote = true;
                }
                for (const auto& parameter : method->parameters) {
                    if (wrote) {
                        out << ", ";
                    }
                    out << c_type_name(parameter.type) << " " << sanitize_c_name(parameter.name);
                    wrote = true;
                }
                if (!wrote) {
                    out << "void";
                }
                out << ") {\n";
                emit_block(out, *program_.methods.at(method.get())->body, 1);
                if (method->return_type == &program_.semantic_model.void_type) {
                    out << "    return;\n";
                }
                out << "}\n\n";
            }
        }
    }

    void emit_main(std::ostringstream& out) {
        if (program_.entry_point == nullptr) {
            return;
        }
        out << "int main(int argc, char** argv) {\n";
        if (!program_.entry_point->parameters.empty()) {
            out << "    HyStringArray hy_args;\n";
            out << "    hy_args.length = argc > 1 ? argc - 1 : 0;\n";
            out << "    hy_args.items = argc > 1 ? (const char**)(argv + 1) : NULL;\n";
            out << "    " << method_name(*program_.entry_point) << "(hy_args);\n";
        } else {
            out << "    " << method_name(*program_.entry_point) << "();\n";
        }
        out << "    return 0;\n";
        out << "}\n";
    }

    void indent(std::ostringstream& out, int level) {
        for (int index = 0; index < level; ++index) {
            out << "    ";
        }
    }

    void emit_statement(std::ostringstream& out, const BoundStatement& statement, int level) {
        switch (statement.kind) {
            case BoundStatementKind::Block:
                emit_block(out, static_cast<const BoundBlockStatement&>(statement), level);
                break;
            case BoundStatementKind::VariableDeclaration: {
                const auto& declaration = static_cast<const BoundVariableDeclarationStatement&>(statement);
                indent(out, level);
                out << c_type_name(declaration.variable->type) << " " << local_name(*declaration.variable);
                if (declaration.initializer != nullptr) {
                    out << " = " << emit_expression(*declaration.initializer);
                } else {
                    out << " = " << default_expression(declaration.variable->type);
                }
                out << ";\n";
                break;
            }
            case BoundStatementKind::Expression: {
                const auto& expression = static_cast<const BoundExpressionStatement&>(statement);
                indent(out, level);
                out << emit_expression(*expression.expression) << ";\n";
                break;
            }
            case BoundStatementKind::If: {
                const auto& if_statement = static_cast<const BoundIfStatement&>(statement);
                indent(out, level);
                out << "if (" << emit_expression(*if_statement.condition) << ") {\n";
                emit_statement(out, *if_statement.then_statement, level + 1);
                indent(out, level);
                out << "}";
                if (if_statement.else_statement != nullptr) {
                    out << " else {\n";
                    emit_statement(out, *if_statement.else_statement, level + 1);
                    indent(out, level);
                    out << "}";
                }
                out << "\n";
                break;
            }
            case BoundStatementKind::While: {
                const auto& while_statement = static_cast<const BoundWhileStatement&>(statement);
                indent(out, level);
                out << "while (" << emit_expression(*while_statement.condition) << ") {\n";
                emit_statement(out, *while_statement.body, level + 1);
                indent(out, level);
                out << "}\n";
                break;
            }
            case BoundStatementKind::Return: {
                const auto& return_statement = static_cast<const BoundReturnStatement&>(statement);
                indent(out, level);
                if (return_statement.expression != nullptr) {
                    out << "return " << emit_expression(*return_statement.expression) << ";\n";
                } else {
                    out << "return;\n";
                }
                break;
            }
        }
    }

    void emit_block(std::ostringstream& out, const BoundBlockStatement& block, int level) {
        for (const auto& statement : block.statements) {
            emit_statement(out, *statement, level);
        }
    }

    string default_expression(const TypeSymbol* type) const {
        switch (type->kind) {
            case TypeKind::Int:
                return "0";
            case TypeKind::Bool:
                return "false";
            case TypeKind::Array:
                return "(HyStringArray){0, NULL}";
            case TypeKind::String:
            case TypeKind::Class:
            case TypeKind::Null:
            case TypeKind::Error:
                return "NULL";
            case TypeKind::Void:
                return "";
        }
        return "NULL";
    }

    string local_name(const VariableSymbol& variable) const {
        return "local_" + sanitize_c_name(variable.name) + "_" + std::to_string(variable.id);
    }

    string emit_expression(const BoundExpression& expression) {
        switch (expression.kind) {
            case BoundExpressionKind::Literal: {
                const auto& literal = static_cast<const BoundLiteralExpression&>(expression);
                if (std::holds_alternative<int64_t>(literal.value)) {
                    return std::to_string(std::get<int64_t>(literal.value));
                }
                if (std::holds_alternative<bool>(literal.value)) {
                    return std::get<bool>(literal.value) ? "true" : "false";
                }
                if (std::holds_alternative<string>(literal.value)) {
                    return "\"" + escape_c_string(std::get<string>(literal.value)) + "\"";
                }
                return "NULL";
            }
            case BoundExpressionKind::Local: {
                const auto& local = static_cast<const BoundLocalExpression&>(expression);
                return local_name(*local.variable);
            }
            case BoundExpressionKind::Parameter: {
                const auto& parameter = static_cast<const BoundParameterExpression&>(expression);
                return sanitize_c_name(parameter.parameter->name);
            }
            case BoundExpressionKind::ThisReference:
                return "self";
            case BoundExpressionKind::Field: {
                const auto& field = static_cast<const BoundFieldExpression&>(expression);
                if (field.field->is_static) {
                    return static_field_name(*field.field);
                }
                return "(" + emit_expression(*field.receiver) + "->" + sanitize_c_name(field.field->name) + ")";
            }
            case BoundExpressionKind::ArrayLength: {
                const auto& length = static_cast<const BoundArrayLengthExpression&>(expression);
                return "((int64_t)(" + emit_expression(*length.array_expression) + ".length))";
            }
            case BoundExpressionKind::Assignment: {
                const auto& assignment = static_cast<const BoundAssignmentExpression&>(expression);
                return "(" + emit_expression(*assignment.target) + " = " + emit_expression(*assignment.expression) + ")";
            }
            case BoundExpressionKind::Unary: {
                const auto& unary = static_cast<const BoundUnaryExpression&>(expression);
                return "(" + token_text(unary.op) + emit_expression(*unary.operand) + ")";
            }
            case BoundExpressionKind::Binary: {
                const auto& binary = static_cast<const BoundBinaryExpression&>(expression);
                return "(" + emit_expression(*binary.left) + " " + token_text(binary.op) + " " + emit_expression(*binary.right) + ")";
            }
            case BoundExpressionKind::Call: {
                const auto& call = static_cast<const BoundCallExpression&>(expression);
                if (call.method->is_builtin && call.method->owner == program_.semantic_model.console_class) {
                    string function_name = "hy_console_writeline_string";
                    if (call.method == program_.semantic_model.console_writeline_int) {
                        function_name = "hy_console_writeline_int";
                    } else if (call.method == program_.semantic_model.console_writeline_bool) {
                        function_name = "hy_console_writeline_bool";
                    }
                    return function_name + "(" + emit_expression(*call.arguments[0]) + ")";
                }

                std::ostringstream builder;
                builder << method_name(*call.method) << "(";
                bool wrote = false;
                if (call.receiver != nullptr) {
                    builder << emit_expression(*call.receiver);
                    wrote = true;
                }
                for (std::size_t index = 0; index < call.arguments.size(); ++index) {
                    if (wrote) {
                        builder << ", ";
                    }
                    builder << emit_expression(*call.arguments[index]);
                    wrote = true;
                }
                if (!wrote) {
                    builder << "void";
                }
                builder << ")";
                string result = builder.str();
                if (result.find("(void)") != string::npos) {
                    result.erase(result.find("void"), 4);
                }
                return result;
            }
            case BoundExpressionKind::NewObject: {
                const auto& creation = static_cast<const BoundNewExpression&>(expression);
                std::ostringstream builder;
                const int arity = creation.constructor != nullptr ? static_cast<int>(creation.constructor->parameters.size()) : 0;
                builder << new_helper_name(*creation.class_symbol, arity) << "(";
                for (std::size_t index = 0; index < creation.arguments.size(); ++index) {
                    if (index > 0) {
                        builder << ", ";
                    }
                    builder << emit_expression(*creation.arguments[index]);
                }
                if (creation.arguments.empty()) {
                    builder << "void";
                }
                builder << ")";
                string result = builder.str();
                if (result.find("(void)") != string::npos) {
                    result.erase(result.find("void"), 4);
                }
                return result;
            }
        }
        return "NULL";
    }

    string token_text(TokenKind kind) const {
        switch (kind) {
            case TokenKind::Plus:
                return "+";
            case TokenKind::Minus:
                return "-";
            case TokenKind::Star:
                return "*";
            case TokenKind::Slash:
                return "/";
            case TokenKind::Bang:
                return "!";
            case TokenKind::EqualsEquals:
                return "==";
            case TokenKind::BangEquals:
                return "!=";
            case TokenKind::Less:
                return "<";
            case TokenKind::LessEquals:
                return "<=";
            case TokenKind::Greater:
                return ">";
            case TokenKind::GreaterEquals:
                return ">=";
            case TokenKind::AmpAmp:
                return "&&";
            case TokenKind::PipePipe:
                return "||";
            default:
                return "";
        }
    }

    const BoundProgram& program_;
};

struct ProjectManifest {
    string name;
    string type = "exe";
    vector<fs::path> sources;
    vector<fs::path> references;
};

std::optional<ProjectManifest> load_project_manifest(const fs::path& path, DiagnosticBag& diagnostics) {
    std::ifstream input(path);
    if (!input) {
        diagnostics.add(path, 1, 1, "Could not open project manifest");
        return std::nullopt;
    }

    ProjectManifest manifest;
    string line;
    int line_number = 0;
    while (std::getline(input, line)) {
        ++line_number;
        line = trim(line);
        if (line.empty() || starts_with(line, "#")) {
            continue;
        }

        const auto equals = line.find('=');
        if (equals == string::npos) {
            diagnostics.add(path, line_number, 1, "Expected '=' in project manifest");
            continue;
        }

        const string key = trim(line.substr(0, equals));
        const string value = trim(line.substr(equals + 1));
        auto parse_string_value = [&](const string& raw) -> string {
            if (raw.size() >= 2 && raw.front() == '"' && raw.back() == '"') {
                return raw.substr(1, raw.size() - 2);
            }
            diagnostics.add(path, line_number, static_cast<int>(equals + 2), "Expected quoted string value");
            return {};
        };

        auto parse_array = [&](const string& raw) -> vector<fs::path> {
            vector<fs::path> result;
            if (raw.size() < 2 || raw.front() != '[' || raw.back() != ']') {
                diagnostics.add(path, line_number, static_cast<int>(equals + 2), "Expected array value");
                return result;
            }
            string inner = trim(raw.substr(1, raw.size() - 2));
            if (inner.empty()) {
                return result;
            }
            std::size_t cursor = 0;
            while (cursor < inner.size()) {
                while (cursor < inner.size() && std::isspace(static_cast<unsigned char>(inner[cursor]))) {
                    ++cursor;
                }
                if (cursor >= inner.size() || inner[cursor] != '"') {
                    diagnostics.add(path, line_number, static_cast<int>(equals + 2 + cursor), "Expected string element");
                    break;
                }
                ++cursor;
                string item;
                while (cursor < inner.size() && inner[cursor] != '"') {
                    item.push_back(inner[cursor++]);
                }
                if (cursor >= inner.size()) {
                    diagnostics.add(path, line_number, static_cast<int>(equals + 2 + cursor), "Unterminated string in array");
                    break;
                }
                ++cursor;
                result.push_back(item);
                while (cursor < inner.size() && std::isspace(static_cast<unsigned char>(inner[cursor]))) {
                    ++cursor;
                }
                if (cursor < inner.size()) {
                    if (inner[cursor] != ',') {
                        diagnostics.add(path, line_number, static_cast<int>(equals + 2 + cursor), "Expected ',' between array items");
                        break;
                    }
                    ++cursor;
                }
            }
            return result;
        };

        if (key == "name") {
            manifest.name = parse_string_value(value);
        } else if (key == "type") {
            manifest.type = parse_string_value(value);
        } else if (key == "sources") {
            manifest.sources = parse_array(value);
        } else if (key == "references") {
            manifest.references = parse_array(value);
        } else {
            diagnostics.add(path, line_number, 1, "Unknown project key '" + key + "'");
        }
    }

    if (manifest.name.empty()) {
        manifest.name = path.stem().string();
    }

    return manifest;
}

bool read_text_file(const fs::path& path, string& output) {
    std::ifstream input(path);
    if (!input) {
        return false;
    }
    std::ostringstream buffer;
    buffer << input.rdbuf();
    output = buffer.str();
    return true;
}

void collect_project_sources(const fs::path& path,
                             std::vector<fs::path>& sources,
                             std::unordered_set<string>& visited_projects,
                             DiagnosticBag& diagnostics) {
    const fs::path canonical = fs::weakly_canonical(path);
    if (!visited_projects.insert(canonical.string()).second) {
        return;
    }

    const auto manifest = load_project_manifest(canonical, diagnostics);
    if (!manifest.has_value()) {
        return;
    }

    const fs::path base_dir = canonical.parent_path();
    for (const auto& source : manifest->sources) {
        sources.push_back(fs::weakly_canonical(base_dir / source));
    }
    for (const auto& reference : manifest->references) {
        collect_project_sources(base_dir / reference, sources, visited_projects, diagnostics);
    }
}

vector<CompilationUnitSyntax> parse_units(const vector<fs::path>& source_files, DiagnosticBag& diagnostics) {
    vector<CompilationUnitSyntax> units;
    for (const auto& source_file : source_files) {
        string source_text;
        if (!read_text_file(source_file, source_text)) {
            diagnostics.add(source_file, 1, 1, "Could not read source file");
            continue;
        }
        Lexer lexer(source_file, source_text, diagnostics);
        Parser parser(source_file, lexer.lex(), diagnostics);
        units.push_back(parser.parse());
    }
    return units;
}

std::unique_ptr<BoundProgram> load_program_from_target(const fs::path& input_path, DiagnosticBag& diagnostics) {
    vector<fs::path> source_files;
    if (input_path.extension() == ".hyproj") {
        std::unordered_set<string> visited_projects;
        collect_project_sources(input_path, source_files, visited_projects, diagnostics);
    } else {
        source_files.push_back(fs::weakly_canonical(input_path));
    }

    std::sort(source_files.begin(), source_files.end());
    source_files.erase(std::unique(source_files.begin(), source_files.end()), source_files.end());
    auto units = parse_units(source_files, diagnostics);
    if (diagnostics.has_errors()) {
        return nullptr;
    }

    SemanticBuilder builder(std::move(units), diagnostics);
    auto program = builder.build();
    if (diagnostics.has_errors()) {
        return nullptr;
    }

    return program;
}

std::optional<ProjectManifest> manifest_for_target(const fs::path& input_path, DiagnosticBag& diagnostics) {
    if (input_path.extension() == ".hyproj") {
        return load_project_manifest(input_path, diagnostics);
    }
    ProjectManifest manifest;
    manifest.name = input_path.stem().string();
    manifest.type = "exe";
    manifest.sources.push_back(input_path.filename());
    return manifest;
}

string quote(const fs::path& value) {
    return "\"" + value.string() + "\"";
}

bool command_exists(const string& command) {
#ifdef _WIN32
    const string check = "where " + command + " >nul 2>nul";
#else
    const string check = "command -v " + command + " >/dev/null 2>&1";
#endif
    return std::system(check.c_str()) == 0;
}

struct HostToolchain {
    string c_compiler;
    string archiver;
    bool uses_msvc = false;
};

std::optional<HostToolchain> detect_host_toolchain() {
    const char* env_cc = std::getenv("CC");
    if (env_cc != nullptr && *env_cc != '\0') {
        HostToolchain toolchain;
        toolchain.c_compiler = env_cc;
        toolchain.archiver = command_exists("ar") ? "ar" : "";
        return toolchain;
    }

#ifdef _WIN32
    if (command_exists("cl")) {
        HostToolchain toolchain;
        toolchain.c_compiler = "cl";
        toolchain.archiver = command_exists("lib") ? "lib" : "";
        toolchain.uses_msvc = true;
        return toolchain;
    }
#endif

    for (const string candidate : {"cc", "clang", "gcc"}) {
        if (command_exists(candidate)) {
            HostToolchain toolchain;
            toolchain.c_compiler = candidate;
            toolchain.archiver = command_exists("ar") ? "ar" : "";
            return toolchain;
        }
    }
    return std::nullopt;
}

fs::path default_output_path(const fs::path& input_path, const ProjectManifest& manifest, const string& target_type) {
    const fs::path build_dir = input_path.parent_path() / ".hylang";
    if (target_type == "lib") {
#ifdef _WIN32
        return build_dir / (manifest.name + ".lib");
#else
        return build_dir / ("lib" + manifest.name + ".a");
#endif
    }
#ifdef _WIN32
    return build_dir / (manifest.name + ".exe");
#else
    return build_dir / manifest.name;
#endif
}

bool write_text_file(const fs::path& path, const string& contents) {
    std::ofstream output(path);
    if (!output) {
        return false;
    }
    output << contents;
    return true;
}

}  // namespace

RunResult run_target(const RunOptions& options) {
    DiagnosticBag diagnostics;
    const auto program = load_program_from_target(options.input_path, diagnostics);
    if (!program) {
        return RunResult{false, std::move(diagnostics.items)};
    }
    if (!locate_entry_point(*program, diagnostics)) {
        return RunResult{false, std::move(diagnostics.items)};
    }

    Interpreter interpreter(*program);
    if (!interpreter.run(options.args)) {
        diagnostics.add(options.input_path, 1, 1, "Interpreter could not start the program");
        return RunResult{false, std::move(diagnostics.items)};
    }

    return RunResult{true, {}};
}

BuildResult build_target(const BuildOptions& options) {
    DiagnosticBag diagnostics;
    const auto manifest = manifest_for_target(options.input_path, diagnostics);
    if (!manifest.has_value()) {
        return BuildResult{false, std::move(diagnostics.items), {}};
    }

    const auto program = load_program_from_target(options.input_path, diagnostics);
    if (!program) {
        return BuildResult{false, std::move(diagnostics.items), {}};
    }

    const string target_type = options.forced_target.value_or(manifest->type);
    if (target_type != "exe" && target_type != "lib") {
        diagnostics.add(options.input_path, 1, 1, "Unsupported build target '" + target_type + "'");
        return BuildResult{false, std::move(diagnostics.items), {}};
    }
    if (target_type == "exe" && !locate_entry_point(*program, diagnostics)) {
        return BuildResult{false, std::move(diagnostics.items), {}};
    }

    const auto toolchain = detect_host_toolchain();
    if (!toolchain.has_value()) {
        diagnostics.add(options.input_path, 1, 1, "Could not find a host C compiler");
        return BuildResult{false, std::move(diagnostics.items), {}};
    }

    const fs::path output_path = options.output_path.value_or(default_output_path(options.input_path, *manifest, target_type));
    const fs::path build_dir = output_path.parent_path().empty() ? fs::current_path() : output_path.parent_path();
    fs::create_directories(build_dir);

    CEmitter emitter(*program);
    const string c_source = target_type == "lib" ? emitter.emit_library() : emitter.emit_executable();
    const fs::path generated_c = build_dir / (manifest->name + ".generated.c");
    if (!write_text_file(generated_c, c_source)) {
        diagnostics.add(generated_c, 1, 1, "Could not write generated C file");
        return BuildResult{false, std::move(diagnostics.items), {}};
    }

    int result = 0;
    if (target_type == "exe") {
        string command;
        if (toolchain->uses_msvc) {
            command = toolchain->c_compiler + " /nologo /std:c11 " + quote(generated_c) + " /Fe:" + quote(output_path);
        } else {
            command = toolchain->c_compiler + " -std=c11 " + quote(generated_c) + " -o " + quote(output_path);
        }
        result = std::system(command.c_str());
    } else {
        const fs::path object_path = build_dir / (manifest->name + ".generated.o");
        string compile_command;
        if (toolchain->uses_msvc) {
            compile_command = toolchain->c_compiler + " /nologo /std:c11 /c " + quote(generated_c) + " /Fo:" + quote(object_path);
        } else {
            compile_command = toolchain->c_compiler + " -std=c11 -c " + quote(generated_c) + " -o " + quote(object_path);
        }
        result = std::system(compile_command.c_str());
        if (result == 0) {
            string archive_command;
            if (toolchain->uses_msvc) {
                archive_command = "lib /nologo /OUT:" + quote(output_path) + " " + quote(object_path);
            } else if (!toolchain->archiver.empty()) {
                archive_command = toolchain->archiver + " rcs " + quote(output_path) + " " + quote(object_path);
            } else {
                diagnostics.add(options.input_path, 1, 1, "Could not find a host archiver for static library output");
                return BuildResult{false, std::move(diagnostics.items), {}};
            }
            result = std::system(archive_command.c_str());
        }
    }

    if (result != 0) {
        diagnostics.add(generated_c, 1, 1, "Host toolchain failed while compiling generated C");
        return BuildResult{false, std::move(diagnostics.items), {}};
    }

    return BuildResult{true, {}, output_path};
}

std::string format_diagnostics(const std::vector<Diagnostic>& diagnostics) {
    std::ostringstream out;
    for (const auto& diagnostic : diagnostics) {
        if (!diagnostic.file.empty()) {
            out << diagnostic.file.string() << ":";
        }
        out << diagnostic.line << ":" << diagnostic.column << ": " << diagnostic.message << "\n";
    }
    return out.str();
}

}  // namespace hylang
