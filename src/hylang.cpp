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
    Percent,
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
    Struct,
    Interface,
    Enum,
    Public,
    Private,
    Protected,
    Internal,
    Static,
    Virtual,
    Override,
    Void,
    Int,
    StringKeyword,
    Bool,
    Var,
    True,
    False,
    Null,
    If,
    Else,
    While,
    For,
    Break,
    Continue,
    Return,
    New,
    This,
    Base,
    Colon,
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
                case ':':
                    tokens.push_back(Token{TokenKind::Colon, ":", line, column});
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
                case '%':
                    tokens.push_back(Token{TokenKind::Percent, "%", line, column});
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
            {"struct", TokenKind::Struct},
            {"interface", TokenKind::Interface},
            {"enum", TokenKind::Enum},
            {"public", TokenKind::Public},
            {"private", TokenKind::Private},
            {"protected", TokenKind::Protected},
            {"internal", TokenKind::Internal},
            {"static", TokenKind::Static},
            {"virtual", TokenKind::Virtual},
            {"override", TokenKind::Override},
            {"void", TokenKind::Void},
            {"int", TokenKind::Int},
            {"string", TokenKind::StringKeyword},
            {"bool", TokenKind::Bool},
            {"var", TokenKind::Var},
            {"true", TokenKind::True},
            {"false", TokenKind::False},
            {"null", TokenKind::Null},
            {"if", TokenKind::If},
            {"else", TokenKind::Else},
            {"while", TokenKind::While},
            {"for", TokenKind::For},
            {"break", TokenKind::Break},
            {"continue", TokenKind::Continue},
            {"return", TokenKind::Return},
            {"new", TokenKind::New},
            {"this", TokenKind::This},
            {"base", TokenKind::Base},
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
                    case 'r':
                        value.push_back('\r');
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
    vector<TypeSyntax> type_arguments;
    int array_rank = 0;
    bool is_var = false;
    int line = 1;
    int column = 1;
};

enum class ModifierKind {
    Public,
    Private,
    Protected,
    Internal,
    Static,
    Virtual,
    Override,
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

struct BaseExpressionSyntax final : ExpressionSyntax {};

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

struct ElementAccessExpressionSyntax final : ExpressionSyntax {
    unique_ptr<ExpressionSyntax> target;
    unique_ptr<ExpressionSyntax> index;
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

struct ForStatementSyntax final : StatementSyntax {
    unique_ptr<StatementSyntax> initializer;
    unique_ptr<ExpressionSyntax> condition;
    unique_ptr<ExpressionSyntax> update;
    unique_ptr<StatementSyntax> body;
};

struct BreakStatementSyntax final : StatementSyntax {};

struct ContinueStatementSyntax final : StatementSyntax {};

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
    vector<string> type_parameters;
    vector<ParameterSyntax> parameters;
    unique_ptr<BlockStatementSyntax> body;
};

struct ConstructorDeclarationSyntax final : MemberSyntax {
    string name;
    vector<ParameterSyntax> parameters;
    bool has_base_initializer = false;
    vector<unique_ptr<ExpressionSyntax>> base_arguments;
    unique_ptr<BlockStatementSyntax> body;
};

struct EnumMemberDeclarationSyntax {
    string name;
    int line = 1;
    int column = 1;
};

struct EnumDeclarationSyntax {
    vector<ModifierKind> modifiers;
    string namespace_name;
    string name;
    vector<EnumMemberDeclarationSyntax> members;
    int line = 1;
    int column = 1;
};

enum class TypeDeclarationKind {
    Class,
    Struct,
    Interface,
};

struct ClassDeclarationSyntax {
    vector<ModifierKind> modifiers;
    TypeDeclarationKind kind = TypeDeclarationKind::Class;
    string namespace_name;
    string name;
    vector<string> type_parameters;
    vector<TypeSyntax> base_types;
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
    vector<unique_ptr<EnumDeclarationSyntax>> enums;
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
                    const std::size_t before = index_;
                    parse_namespace_member(unit, namespace_name);
                    if (index_ == before) {
                        advance();
                    }
                }
                consume(TokenKind::CloseBrace, "Expected '}' after namespace block");
                continue;
            }

            const std::size_t before = index_;
            parse_namespace_member(unit, "");
            if (index_ == before) {
                advance();
            }
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

    Token consume(TokenKind kind, const string& message) {
        if (check(kind)) {
            return advance();
        }
        diagnostics_.add(file_, current().line, current().column, message);
        if (!check(TokenKind::EndOfFile) && !should_hold_position_on_missing(kind)) {
            advance();
            return previous();
        }
        return Token{kind, "", current().line, current().column};
    }

    bool should_hold_position_on_missing(TokenKind expected) const {
        if (check(TokenKind::EndOfFile)) {
            return true;
        }

        switch (expected) {
            case TokenKind::Semicolon:
                return check(TokenKind::CloseBrace) ||
                       is_statement_start_token(current().kind) ||
                       is_member_start_token(current().kind) ||
                       is_type_declaration_start_token(current().kind);
            case TokenKind::OpenBrace:
                return check(TokenKind::CloseBrace) ||
                       is_member_start_token(current().kind) ||
                       is_type_declaration_start_token(current().kind) ||
                       is_statement_start_token(current().kind);
            case TokenKind::CloseBrace:
                return is_member_start_token(current().kind) ||
                       is_type_declaration_start_token(current().kind);
            case TokenKind::CloseParen:
                return check(TokenKind::OpenBrace) || check(TokenKind::Semicolon) || check(TokenKind::CloseBrace);
            case TokenKind::CloseBracket:
                return check(TokenKind::Semicolon) || check(TokenKind::CloseParen) || check(TokenKind::CloseBrace);
            default:
                return false;
        }
    }

    void parse_namespace_member(CompilationUnitSyntax& unit, const string& namespace_name) {
        const auto modifiers = parse_modifiers();
        if (check(TokenKind::Class)) {
            unit.classes.push_back(parse_type_declaration(namespace_name, modifiers, TypeDeclarationKind::Class));
            return;
        }
        if (check(TokenKind::Struct)) {
            unit.classes.push_back(parse_type_declaration(namespace_name, modifiers, TypeDeclarationKind::Struct));
            return;
        }
        if (check(TokenKind::Interface)) {
            unit.classes.push_back(parse_type_declaration(namespace_name, modifiers, TypeDeclarationKind::Interface));
            return;
        }
        if (check(TokenKind::Enum)) {
            unit.enums.push_back(parse_enum_declaration(namespace_name, modifiers));
            return;
        }

        diagnostics_.add(file_, current().line, current().column, "Expected type declaration");
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
            } else if (match(TokenKind::Virtual)) {
                modifiers.push_back(ModifierKind::Virtual);
                keep_parsing = true;
            } else if (match(TokenKind::Override)) {
                modifiers.push_back(ModifierKind::Override);
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

    vector<string> parse_type_parameter_names() {
        vector<string> names;
        consume(TokenKind::Less, "Expected '<' to start type parameter list");
        if (check(TokenKind::Greater)) {
            diagnostics_.add(file_, current().line, current().column, "Type parameter list cannot be empty");
        } else {
            do {
                const Token name = consume(TokenKind::Identifier, "Expected type parameter name");
                names.push_back(name.text);
            } while (match(TokenKind::Comma));
        }
        consume(TokenKind::Greater, "Expected '>' after type parameter list");
        return names;
    }

    vector<TypeSyntax> parse_base_type_list() {
        vector<TypeSyntax> types;
        do {
            types.push_back(parse_type_syntax());
        } while (match(TokenKind::Comma));
        return types;
    }

    unique_ptr<ClassDeclarationSyntax> parse_type_declaration(const string& namespace_name,
                                                              vector<ModifierKind> modifiers,
                                                              TypeDeclarationKind kind) {
        auto syntax = std::make_unique<ClassDeclarationSyntax>();
        syntax->modifiers = std::move(modifiers);
        syntax->kind = kind;
        Token declaration_token;
        if (kind == TypeDeclarationKind::Class) {
            declaration_token = consume(TokenKind::Class, "Expected 'class' declaration");
        } else if (kind == TypeDeclarationKind::Struct) {
            declaration_token = consume(TokenKind::Struct, "Expected 'struct' declaration");
        } else {
            declaration_token = consume(TokenKind::Interface, "Expected 'interface' declaration");
        }
        const Token name = consume(TokenKind::Identifier, "Expected class name");
        syntax->namespace_name = namespace_name;
        syntax->name = name.text;
        syntax->line = declaration_token.line;
        syntax->column = declaration_token.column;
        if (check(TokenKind::Less)) {
            syntax->type_parameters = parse_type_parameter_names();
        }
        if (match(TokenKind::Colon)) {
            syntax->base_types = parse_base_type_list();
        }
        consume(TokenKind::OpenBrace, "Expected '{' after type declaration");
        while (!check(TokenKind::CloseBrace) && !check(TokenKind::EndOfFile)) {
            syntax->members.push_back(parse_member_declaration(syntax->name, kind));
        }
        consume(TokenKind::CloseBrace, "Expected '}' after type body");
        return syntax;
    }

    unique_ptr<EnumDeclarationSyntax> parse_enum_declaration(const string& namespace_name,
                                                             vector<ModifierKind> modifiers) {
        auto syntax = std::make_unique<EnumDeclarationSyntax>();
        syntax->modifiers = std::move(modifiers);
        const Token enum_token = consume(TokenKind::Enum, "Expected 'enum' declaration");
        const Token name = consume(TokenKind::Identifier, "Expected enum name");
        syntax->namespace_name = namespace_name;
        syntax->name = name.text;
        syntax->line = enum_token.line;
        syntax->column = enum_token.column;
        consume(TokenKind::OpenBrace, "Expected '{' after enum declaration");
        while (!check(TokenKind::CloseBrace) && !check(TokenKind::EndOfFile)) {
            if (!check(TokenKind::Identifier)) {
                diagnostics_.add(file_, current().line, current().column, "Expected enum member name");
                if (!check(TokenKind::Comma) && !check(TokenKind::CloseBrace) && !check(TokenKind::EndOfFile)) {
                    advance();
                }
                if (match(TokenKind::Comma)) {
                    continue;
                }
                continue;
            }

            const Token member = advance();
            syntax->members.push_back(EnumMemberDeclarationSyntax{member.text, member.line, member.column});
            if (check(TokenKind::CloseBrace)) {
                break;
            }
            consume(TokenKind::Comma, "Expected ',' after enum member");
            if (check(TokenKind::CloseBrace)) {
                break;
            }
        }
        consume(TokenKind::CloseBrace, "Expected '}' after enum body");
        return syntax;
    }

    unique_ptr<MemberSyntax> parse_member_declaration(const string& class_name, TypeDeclarationKind owner_kind) {
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
            if (match(TokenKind::Colon)) {
                constructor->has_base_initializer = true;
                consume(TokenKind::Base, "Expected 'base' in constructor initializer");
                consume(TokenKind::OpenParen, "Expected '(' after 'base'");
                if (!check(TokenKind::CloseParen)) {
                    do {
                        constructor->base_arguments.push_back(parse_expression());
                    } while (match(TokenKind::Comma));
                }
                consume(TokenKind::CloseParen, "Expected ')' after base arguments");
            }
            constructor->body = parse_block_statement();
            return constructor;
        }

        TypeSyntax type = parse_type_syntax();
        const Token name = consume(TokenKind::Identifier, "Expected member name");
        vector<string> type_parameters;
        if (check(TokenKind::Less)) {
            type_parameters = parse_type_parameter_names();
        }
        if (match(TokenKind::OpenParen)) {
            auto method = std::make_unique<MethodDeclarationSyntax>();
            method->modifiers = modifiers;
            method->line = name.line;
            method->column = name.column;
            method->return_type = std::move(type);
            method->name = name.text;
            method->type_parameters = std::move(type_parameters);
            method->parameters = parse_parameter_list();
            consume(TokenKind::CloseParen, "Expected ')' after parameter list");
            if (owner_kind == TypeDeclarationKind::Interface) {
                consume(TokenKind::Semicolon, "Expected ';' after interface method declaration");
            } else {
                method->body = parse_block_statement();
            }
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

        if (check(TokenKind::Var)) {
            type.is_var = true;
            type.name_parts.push_back(advance().text);
        } else if (check(TokenKind::Void)) {
            type.name_parts.push_back(advance().text);
        } else if (check(TokenKind::Identifier) || is_builtin_type_token(current().kind)) {
            type.name_parts.push_back(advance().text);
            while (match(TokenKind::Dot)) {
                const Token name = consume(TokenKind::Identifier, "Expected identifier after '.'");
                type.name_parts.push_back(name.text);
            }
            if (match(TokenKind::Less)) {
                if (!check(TokenKind::Greater)) {
                    do {
                        type.type_arguments.push_back(parse_type_syntax());
                    } while (match(TokenKind::Comma));
                }
                consume(TokenKind::Greater, "Expected '>' after type arguments");
            }
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
        if (!(tokens_[cursor].kind == TokenKind::Identifier ||
              is_builtin_type_token(tokens_[cursor].kind) ||
              tokens_[cursor].kind == TokenKind::Var)) {
            return false;
        }

        ++cursor;
        if (tokens_[cursor - 1].kind == TokenKind::Identifier && tokens_[cursor].kind == TokenKind::Less) {
            int depth = 1;
            ++cursor;
            while (cursor < tokens_.size() && depth > 0) {
                if (tokens_[cursor].kind == TokenKind::Less) {
                    ++depth;
                } else if (tokens_[cursor].kind == TokenKind::Greater) {
                    --depth;
                }
                ++cursor;
            }
        }
        while (tokens_[cursor].kind == TokenKind::Dot && tokens_[cursor + 1].kind == TokenKind::Identifier) {
            cursor += 2;
            if (tokens_[cursor].kind == TokenKind::Less) {
                int depth = 1;
                ++cursor;
                while (cursor < tokens_.size() && depth > 0) {
                    if (tokens_[cursor].kind == TokenKind::Less) {
                        ++depth;
                    } else if (tokens_[cursor].kind == TokenKind::Greater) {
                        --depth;
                    }
                    ++cursor;
                }
            }
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
        if (match(TokenKind::For)) {
            return parse_for_statement(previous());
        }
        if (match(TokenKind::Break)) {
            return parse_break_statement(previous());
        }
        if (match(TokenKind::Continue)) {
            return parse_continue_statement(previous());
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

    unique_ptr<StatementSyntax> parse_for_statement(const Token& token) {
        consume(TokenKind::OpenParen, "Expected '(' after 'for'");
        auto statement = std::make_unique<ForStatementSyntax>();
        statement->line = token.line;
        statement->column = token.column;
        if (!check(TokenKind::Semicolon)) {
            if (looks_like_variable_declaration()) {
                statement->initializer = parse_variable_declaration_statement(false);
            } else {
                statement->initializer = parse_expression_statement_syntax(false);
            }
        }
        consume(TokenKind::Semicolon, "Expected ';' after for initializer");
        if (!check(TokenKind::Semicolon)) {
            statement->condition = parse_expression();
        }
        consume(TokenKind::Semicolon, "Expected ';' after for condition");
        if (!check(TokenKind::CloseParen)) {
            statement->update = parse_expression();
        }
        consume(TokenKind::CloseParen, "Expected ')' after for clauses");
        statement->body = parse_statement();
        return statement;
    }

    unique_ptr<StatementSyntax> parse_break_statement(const Token& token) {
        auto statement = std::make_unique<BreakStatementSyntax>();
        statement->line = token.line;
        statement->column = token.column;
        consume(TokenKind::Semicolon, "Expected ';' after break statement");
        return statement;
    }

    unique_ptr<StatementSyntax> parse_continue_statement(const Token& token) {
        auto statement = std::make_unique<ContinueStatementSyntax>();
        statement->line = token.line;
        statement->column = token.column;
        consume(TokenKind::Semicolon, "Expected ';' after continue statement");
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
        return parse_variable_declaration_statement(true);
    }

    unique_ptr<VariableDeclarationStatementSyntax> parse_variable_declaration_statement(bool require_semicolon) {
        auto statement = std::make_unique<VariableDeclarationStatementSyntax>();
        statement->line = current().line;
        statement->column = current().column;
        statement->type = parse_type_syntax();
        const Token name = consume(TokenKind::Identifier, "Expected variable name");
        statement->name = name.text;
        if (match(TokenKind::Equals)) {
            statement->initializer = parse_expression();
        }
        if (require_semicolon) {
            consume(TokenKind::Semicolon, "Expected ';' after variable declaration");
        }
        return statement;
    }

    unique_ptr<StatementSyntax> parse_expression_statement() {
        return parse_expression_statement_syntax(true);
    }

    unique_ptr<ExpressionStatementSyntax> parse_expression_statement_syntax(bool require_semicolon) {
        auto statement = std::make_unique<ExpressionStatementSyntax>();
        statement->line = current().line;
        statement->column = current().column;
        statement->expression = parse_expression();
        if (require_semicolon) {
            consume(TokenKind::Semicolon, "Expected ';' after expression");
        }
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
        while (match(TokenKind::Star) || match(TokenKind::Slash) || match(TokenKind::Percent)) {
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

            if (match(TokenKind::OpenBracket)) {
                auto access = std::make_unique<ElementAccessExpressionSyntax>();
                access->line = previous().line;
                access->column = previous().column;
                access->target = std::move(expression);
                access->index = parse_expression();
                consume(TokenKind::CloseBracket, "Expected ']' after index expression");
                expression = std::move(access);
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
        if (match(TokenKind::Base)) {
            auto expression = std::make_unique<BaseExpressionSyntax>();
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

    static bool is_modifier_token(TokenKind kind) {
        return kind == TokenKind::Public ||
               kind == TokenKind::Private ||
               kind == TokenKind::Protected ||
               kind == TokenKind::Internal ||
               kind == TokenKind::Static ||
               kind == TokenKind::Virtual ||
               kind == TokenKind::Override;
    }

    static bool is_type_declaration_start_token(TokenKind kind) {
        return kind == TokenKind::Class ||
               kind == TokenKind::Struct ||
               kind == TokenKind::Interface ||
               kind == TokenKind::Enum ||
               is_modifier_token(kind);
    }

    static bool is_member_start_token(TokenKind kind) {
        return is_type_declaration_start_token(kind) ||
               kind == TokenKind::Identifier ||
               kind == TokenKind::Void ||
               kind == TokenKind::Var ||
               is_builtin_type_token(kind);
    }

    static bool is_expression_start_token(TokenKind kind) {
        return kind == TokenKind::Identifier ||
               kind == TokenKind::Number ||
               kind == TokenKind::StringLiteral ||
               kind == TokenKind::True ||
               kind == TokenKind::False ||
               kind == TokenKind::Null ||
               kind == TokenKind::This ||
               kind == TokenKind::Base ||
               kind == TokenKind::New ||
               kind == TokenKind::OpenParen ||
               kind == TokenKind::Bang ||
               kind == TokenKind::Minus ||
               kind == TokenKind::Plus;
    }

    static bool is_statement_start_token(TokenKind kind) {
        return kind == TokenKind::OpenBrace ||
               kind == TokenKind::If ||
               kind == TokenKind::While ||
               kind == TokenKind::For ||
               kind == TokenKind::Break ||
               kind == TokenKind::Continue ||
               kind == TokenKind::Return ||
               kind == TokenKind::Var ||
               is_expression_start_token(kind) ||
               is_builtin_type_token(kind);
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
    Struct,
    Interface,
    Enum,
    TypeParameter,
    Error,
};

enum class Accessibility {
    Private,
    Protected,
    Internal,
    Public,
};

struct ClassSymbol;
struct EnumSymbol;

struct TypeSymbol {
    TypeKind kind = TypeKind::Error;
    string display_name = "error";
    const TypeSymbol* element_type = nullptr;
    const ClassSymbol* class_symbol = nullptr;
    const EnumSymbol* enum_symbol = nullptr;
    const TypeSymbol* type_parameter_symbol = nullptr;
    vector<const TypeSymbol*> type_arguments;
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
    const FieldDeclarationSyntax* syntax = nullptr;
};

struct MethodSymbol {
    string name;
    const TypeSymbol* return_type = nullptr;
    vector<ParameterSymbol> parameters;
    vector<const TypeSymbol*> type_parameters;
    bool is_static = false;
    bool is_builtin = false;
    bool is_virtual = false;
    bool is_override = false;
    int slot = 0;
    int virtual_slot = -1;
    const ClassSymbol* owner = nullptr;
    const MethodSymbol* overridden_method = nullptr;
    const MethodSymbol* virtual_root = nullptr;
    const MethodSymbol* generic_definition = nullptr;
    vector<const TypeSymbol*> type_arguments;
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

struct EnumMemberSymbol {
    string name;
    int64_t value = 0;
    const EnumSymbol* owner = nullptr;
};

struct ClassSymbol {
    TypeKind kind = TypeKind::Class;
    string namespace_name;
    string name;
    string full_name;
    fs::path source_file;
    bool is_builtin = false;
    vector<string> using_namespaces;
    vector<const TypeSymbol*> type_parameters;
    const ClassSymbol* generic_definition = nullptr;
    vector<const TypeSymbol*> type_arguments;
    const ClassDeclarationSyntax* syntax = nullptr;
    const ClassSymbol* base_class = nullptr;
    vector<const ClassSymbol*> interfaces;
    vector<const TypeSymbol*> interface_types;
    vector<std::unique_ptr<FieldSymbol>> fields;
    vector<std::unique_ptr<MethodSymbol>> methods;
    vector<std::unique_ptr<ConstructorSymbol>> constructors;
};

struct EnumSymbol {
    string namespace_name;
    string name;
    string full_name;
    fs::path source_file;
    Accessibility accessibility = Accessibility::Private;
    const EnumDeclarationSyntax* syntax = nullptr;
    vector<std::unique_ptr<EnumMemberSymbol>> members;
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
    ArrayIndex,
    StringIndex,
    StringLength,
    Assignment,
    Conversion,
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
    For,
    Break,
    Continue,
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

struct BoundArrayIndexExpression final : BoundExpression {
    std::unique_ptr<BoundExpression> array_expression;
    std::unique_ptr<BoundExpression> index_expression;
};

struct BoundStringIndexExpression final : BoundExpression {
    std::unique_ptr<BoundExpression> string_expression;
    std::unique_ptr<BoundExpression> index_expression;
};

struct BoundStringLengthExpression final : BoundExpression {
    std::unique_ptr<BoundExpression> string_expression;
};

struct BoundAssignmentExpression final : BoundExpression {
    std::unique_ptr<BoundExpression> target;
    std::unique_ptr<BoundExpression> expression;
};

struct BoundConversionExpression final : BoundExpression {
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
    bool dispatch_virtual = false;
    bool dispatch_interface = false;
    const TypeSymbol* dispatch_type = nullptr;
};

struct BoundNewExpression final : BoundExpression {
    const ClassSymbol* class_symbol = nullptr;
    const ConstructorSymbol* constructor = nullptr;
    vector<std::unique_ptr<BoundExpression>> arguments;
    bool zero_initialize = false;
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

struct BoundForStatement final : BoundStatement {
    std::unique_ptr<BoundStatement> initializer;
    std::unique_ptr<BoundExpression> condition;
    std::unique_ptr<BoundExpression> update;
    std::unique_ptr<BoundStatement> body;
};

struct BoundBreakStatement final : BoundStatement {};

struct BoundContinueStatement final : BoundStatement {};

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
    const ConstructorSymbol* base_constructor = nullptr;
    vector<std::unique_ptr<BoundExpression>> base_arguments;
};

struct SemanticModel {
    std::vector<std::unique_ptr<TypeSymbol>> owned_types;
    std::unordered_map<string, TypeSymbol*> array_types;
    TypeSymbol void_type{TypeKind::Void, "void", nullptr, nullptr, nullptr, nullptr, {}};
    TypeSymbol int_type{TypeKind::Int, "int", nullptr, nullptr, nullptr, nullptr, {}};
    TypeSymbol bool_type{TypeKind::Bool, "bool", nullptr, nullptr, nullptr, nullptr, {}};
    TypeSymbol string_type{TypeKind::String, "string", nullptr, nullptr, nullptr, nullptr, {}};
    TypeSymbol null_type{TypeKind::Null, "null", nullptr, nullptr, nullptr, nullptr, {}};
    TypeSymbol error_type{TypeKind::Error, "error", nullptr, nullptr, nullptr, nullptr, {}};
    std::vector<std::unique_ptr<ClassSymbol>> classes;
    std::unordered_map<string, ClassSymbol*> classes_by_full_name;
    std::vector<std::unique_ptr<EnumSymbol>> enums;
    std::unordered_map<string, EnumSymbol*> enums_by_full_name;
    std::vector<std::unique_ptr<MethodSymbol>> owned_method_specializations;
    std::vector<std::unique_ptr<ConstructorSymbol>> owned_constructor_specializations;
    std::unordered_set<string> namespaces;
    ClassSymbol* console_class = nullptr;
    ClassSymbol* file_class = nullptr;
    MethodSymbol* console_write_string = nullptr;
    MethodSymbol* console_write_int = nullptr;
    MethodSymbol* console_write_bool = nullptr;
    MethodSymbol* console_writeline_string = nullptr;
    MethodSymbol* console_writeline_int = nullptr;
    MethodSymbol* console_writeline_bool = nullptr;
    MethodSymbol* file_exists = nullptr;
    MethodSymbol* file_read_all_text = nullptr;
    MethodSymbol* file_write_all_text = nullptr;
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

bool is_same_or_derived_from(const ClassSymbol* derived, const ClassSymbol* base) {
    for (auto current = derived; current != nullptr; current = current->base_class) {
        if (current == base) {
            return true;
        }
    }
    return false;
}

bool is_inherited_accessible(Accessibility accessibility) {
    return accessibility != Accessibility::Private;
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
        case Accessibility::Protected:
            return is_same_or_derived_from(&current_class, &owner);
        case Accessibility::Private:
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

bool are_types_equal(const TypeSymbol* left, const TypeSymbol* right);

bool is_reference_type(const TypeSymbol* type) {
    if (type == nullptr) {
        return false;
    }
    return type->kind == TypeKind::Class ||
           type->kind == TypeKind::Interface ||
           type->kind == TypeKind::String ||
           type->kind == TypeKind::Array;
}

bool does_type_implement_interface_symbol(const ClassSymbol* candidate, const ClassSymbol* interface_symbol) {
    if (candidate == nullptr || interface_symbol == nullptr || interface_symbol->kind != TypeKind::Interface) {
        return false;
    }

    for (const auto* declared : candidate->interfaces) {
        if (declared == interface_symbol || does_type_implement_interface_symbol(declared, interface_symbol)) {
            return true;
        }
    }

    if (candidate->base_class != nullptr) {
        return does_type_implement_interface_symbol(candidate->base_class, interface_symbol);
    }

    return false;
}

bool does_type_implement_interface(const ClassSymbol* candidate, const TypeSymbol* interface_type) {
    if (candidate == nullptr || interface_type == nullptr || interface_type->kind != TypeKind::Interface ||
        interface_type->class_symbol == nullptr) {
        return false;
    }

    for (const auto* declared_type : candidate->interface_types) {
        if (are_types_equal(declared_type, interface_type)) {
            return true;
        }
        if (declared_type != nullptr && declared_type->class_symbol != nullptr &&
            declared_type->class_symbol == interface_type->class_symbol && interface_type->type_arguments.empty()) {
            return true;
        }
    }

    if (candidate->base_class != nullptr && does_type_implement_interface(candidate->base_class, interface_type)) {
        return true;
    }

    return does_type_implement_interface_symbol(candidate, interface_type->class_symbol);
}

bool are_types_equal(const TypeSymbol* left, const TypeSymbol* right) {
    if (left == nullptr || right == nullptr) {
        return false;
    }
    if (left == right) {
        return true;
    }
    if (left->kind != right->kind) {
        return false;
    }

    switch (left->kind) {
        case TypeKind::Void:
        case TypeKind::Int:
        case TypeKind::Bool:
        case TypeKind::String:
        case TypeKind::Null:
        case TypeKind::Error:
            return true;
        case TypeKind::TypeParameter:
            return left->type_parameter_symbol == right->type_parameter_symbol || left->display_name == right->display_name;
        case TypeKind::Array:
            return are_types_equal(left->element_type, right->element_type);
        case TypeKind::Class:
        case TypeKind::Struct:
        case TypeKind::Interface:
            if (!(left->class_symbol == right->class_symbol || left->display_name == right->display_name)) {
                return false;
            }
            if (left->type_arguments.size() != right->type_arguments.size()) {
                return false;
            }
            for (std::size_t index = 0; index < left->type_arguments.size(); ++index) {
                if (!are_types_equal(left->type_arguments[index], right->type_arguments[index])) {
                    return false;
                }
            }
            return true;
        case TypeKind::Enum:
            return left->enum_symbol == right->enum_symbol || left->display_name == right->display_name;
    }
    return false;
}

bool is_type_assignable(const TypeSymbol* destination, const TypeSymbol* source) {
    if (destination == nullptr || source == nullptr) {
        return false;
    }
    if (are_types_equal(destination, source)) {
        return true;
    }
    if (destination->kind == TypeKind::Interface && destination->class_symbol != nullptr) {
        if ((source->kind == TypeKind::Class || source->kind == TypeKind::Struct || source->kind == TypeKind::Interface) &&
            source->class_symbol != nullptr) {
            return does_type_implement_interface(source->class_symbol, destination);
        }
    }
    if (destination->kind == source->kind) {
        switch (destination->kind) {
            case TypeKind::Void:
            case TypeKind::Int:
            case TypeKind::Bool:
            case TypeKind::String:
                return false;
            case TypeKind::Class:
                return source->kind == TypeKind::Class &&
                       is_same_or_derived_from(source->class_symbol, destination->class_symbol);
            case TypeKind::Struct:
                return false;
            case TypeKind::Interface:
                if (source->kind == TypeKind::Interface) {
                    return does_type_implement_interface(source->class_symbol, destination);
                }
                if (source->kind == TypeKind::Class || source->kind == TypeKind::Struct) {
                    return does_type_implement_interface(source->class_symbol, destination);
                }
                return false;
            case TypeKind::Enum:
                return destination->enum_symbol == source->enum_symbol ||
                       destination->display_name == source->display_name;
            case TypeKind::Array:
                return destination->element_type != nullptr && source->element_type != nullptr &&
                       is_type_assignable(destination->element_type, source->element_type);
            case TypeKind::Null:
                return true;
            case TypeKind::TypeParameter:
                return false;
            case TypeKind::Error:
                return true;
        }
    }
    if (source->kind == TypeKind::Null && is_reference_type(destination)) {
        return true;
    }
    return false;
}

string member_signature_key(const string& name, bool is_static, const vector<ParameterSymbol>& parameters) {
    std::ostringstream builder;
    builder << name << "#" << (is_static ? "S" : "I");
    for (const auto& parameter : parameters) {
        builder << "#" << parameter.type->display_name;
    }
    return builder.str();
}

bool is_string_concat_operand(const SemanticModel& model, const TypeSymbol* type) {
    return type == &model.string_type || type == &model.int_type || type == &model.bool_type;
}

bool is_string_concatenation(const SemanticModel& model, const TypeSymbol* left, const TypeSymbol* right) {
    if (left == nullptr || right == nullptr) {
        return false;
    }
    return (left == &model.string_type || right == &model.string_type) &&
           is_string_concat_operand(model, left) &&
           is_string_concat_operand(model, right);
}

const TypeSymbol* resolve_type_in_context(SemanticModel& model,
                                          DiagnosticBag& diagnostics,
                                          const fs::path& file,
                                          const TypeSyntax& type,
                                          const string& current_namespace,
                                          const vector<string>& using_namespaces,
                                          const std::unordered_map<string, const TypeSymbol*>* generic_bindings = nullptr) {
    const string name = join_qualified(type.name_parts);
    const TypeSymbol* base = nullptr;

    if (type.is_var) {
        diagnostics.add(file, type.line, type.column, "'var' can only be used for local variables");
        return &model.error_type;
    }
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
    } else if (generic_bindings != nullptr) {
        const auto generic_found = generic_bindings->find(name);
        if (generic_found != generic_bindings->end()) {
            base = generic_found->second;
        }
    }

    if (base == nullptr) {
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

        const ClassSymbol* resolved_named_type = nullptr;
        for (const auto& candidate : candidates) {
            const auto found = model.classes_by_full_name.find(candidate);
            if (found != model.classes_by_full_name.end()) {
                if (resolved_named_type != nullptr && resolved_named_type != found->second) {
                    diagnostics.add(file, type.line, type.column, "Ambiguous type reference '" + name + "'");
                    return &model.error_type;
                }
                resolved_named_type = found->second;
            }
            const auto enum_found = model.enums_by_full_name.find(candidate);
            if (enum_found != model.enums_by_full_name.end()) {
                auto type_symbol = std::make_unique<TypeSymbol>();
                type_symbol->kind = TypeKind::Enum;
                type_symbol->display_name = enum_found->second->full_name;
                type_symbol->enum_symbol = enum_found->second;
                base = type_symbol.get();
                model.owned_types.push_back(std::move(type_symbol));
                break;
            }
        }

        if (base == nullptr && resolved_named_type != nullptr) {
            if (!type.type_arguments.empty() &&
                resolved_named_type->type_parameters.size() != type.type_arguments.size()) {
                diagnostics.add(file, type.line, type.column,
                                "Type '" + resolved_named_type->full_name + "' expects " +
                                    std::to_string(resolved_named_type->type_parameters.size()) + " type argument(s)");
                return &model.error_type;
            }
            if (type.type_arguments.empty() && !resolved_named_type->type_parameters.empty()) {
                diagnostics.add(file, type.line, type.column,
                                "Type '" + resolved_named_type->full_name + "' requires type arguments");
                return &model.error_type;
            }
            auto type_symbol = std::make_unique<TypeSymbol>();
            type_symbol->kind = resolved_named_type->kind;
            type_symbol->display_name = resolved_named_type->full_name;
            type_symbol->class_symbol = resolved_named_type;
            if (!type.type_arguments.empty()) {
                std::ostringstream display_name;
                display_name << resolved_named_type->full_name << "<";
                for (std::size_t index = 0; index < type.type_arguments.size(); ++index) {
                    if (index > 0) {
                        display_name << ", ";
                    }
                    const TypeSymbol* type_argument = resolve_type_in_context(model,
                                                                              diagnostics,
                                                                              file,
                                                                              type.type_arguments[index],
                                                                              current_namespace,
                                                                              using_namespaces,
                                                                              generic_bindings);
                    type_symbol->type_arguments.push_back(type_argument);
                    display_name << type_argument->display_name;
                }
                display_name << ">";
                type_symbol->display_name = display_name.str();
            }
            base = type_symbol.get();
            model.owned_types.push_back(std::move(type_symbol));
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

const TypeSymbol* substitute_type(SemanticModel& model,
                                  const TypeSymbol* type,
                                  const std::unordered_map<const TypeSymbol*, const TypeSymbol*>& substitutions) {
    if (type == nullptr) {
        return nullptr;
    }
    if (type->kind == TypeKind::TypeParameter) {
        const auto found = substitutions.find(type->type_parameter_symbol != nullptr ? type->type_parameter_symbol : type);
        return found != substitutions.end() ? found->second : type;
    }
    if (type->kind == TypeKind::Array && type->element_type != nullptr) {
        const TypeSymbol* substituted_element = substitute_type(model, type->element_type, substitutions);
        if (substituted_element == type->element_type) {
            return type;
        }
        return model.get_array_type(substituted_element);
    }
    if ((type->kind == TypeKind::Class || type->kind == TypeKind::Struct || type->kind == TypeKind::Interface) &&
        !type->type_arguments.empty()) {
        bool changed = false;
        auto clone = std::make_unique<TypeSymbol>();
        *clone = *type;
        clone->type_arguments.clear();
        std::ostringstream display_name;
        display_name << type->class_symbol->full_name << "<";
        for (std::size_t index = 0; index < type->type_arguments.size(); ++index) {
            if (index > 0) {
                display_name << ", ";
            }
            const TypeSymbol* substituted_argument = substitute_type(model, type->type_arguments[index], substitutions);
            clone->type_arguments.push_back(substituted_argument);
            changed = changed || substituted_argument != type->type_arguments[index];
            display_name << substituted_argument->display_name;
        }
        display_name << ">";
        clone->display_name = display_name.str();
        if (!changed) {
            return type;
        }
        const TypeSymbol* raw = clone.get();
        model.owned_types.push_back(std::move(clone));
        return raw;
    }
    return type;
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
        resolve_base_classes(program->semantic_model);
        validate_inheritance_cycles(program->semantic_model);
        declare_enum_members(program->semantic_model);
        declare_members(program->semantic_model);
        validate_inherited_members(program->semantic_model);
        validate_interface_implementations(program->semantic_model);
        validate_base_constructors(program->semantic_model);
        bind_bodies(*program);
        return program;
    }

private:
    void install_builtins(SemanticModel& model) {
        model.namespaces.insert("System");
        model.namespaces.insert("System.IO");

        auto create_builtin_class = [&](const string& namespace_name, const string& class_name) -> ClassSymbol* {
            auto klass = std::make_unique<ClassSymbol>();
            klass->namespace_name = namespace_name;
            klass->name = class_name;
            klass->full_name = namespace_name.empty() ? class_name : namespace_name + "." + class_name;
            klass->is_builtin = true;
            auto* raw = klass.get();
            model.classes_by_full_name[klass->full_name] = raw;
            model.classes.push_back(std::move(klass));
            return raw;
        };

        auto create_builtin = [&](ClassSymbol* owner,
                                  const string& name,
                                  const TypeSymbol* return_type,
                                  const vector<std::pair<string, const TypeSymbol*>>& parameters) -> MethodSymbol* {
            auto method = std::make_unique<MethodSymbol>();
            method->name = name;
            method->return_type = return_type;
            for (std::size_t index = 0; index < parameters.size(); ++index) {
                method->parameters.push_back(ParameterSymbol{parameters[index].first, parameters[index].second, static_cast<int>(index)});
            }
            method->is_static = true;
            method->is_builtin = true;
            method->accessibility = Accessibility::Public;
            method->owner = owner;
            method->slot = static_cast<int>(owner->methods.size());
            auto* raw = method.get();
            owner->methods.push_back(std::move(method));
            return raw;
        };

        model.console_class = create_builtin_class("System", "Console");
        model.console_write_string =
            create_builtin(model.console_class, "Write", &model.void_type, {{"value", &model.string_type}});
        model.console_write_int =
            create_builtin(model.console_class, "Write", &model.void_type, {{"value", &model.int_type}});
        model.console_write_bool =
            create_builtin(model.console_class, "Write", &model.void_type, {{"value", &model.bool_type}});
        model.console_writeline_string =
            create_builtin(model.console_class, "WriteLine", &model.void_type, {{"value", &model.string_type}});
        model.console_writeline_int =
            create_builtin(model.console_class, "WriteLine", &model.void_type, {{"value", &model.int_type}});
        model.console_writeline_bool =
            create_builtin(model.console_class, "WriteLine", &model.void_type, {{"value", &model.bool_type}});

        model.file_class = create_builtin_class("System.IO", "File");
        model.file_exists =
            create_builtin(model.file_class, "Exists", &model.bool_type, {{"path", &model.string_type}});
        model.file_read_all_text =
            create_builtin(model.file_class, "ReadAllText", &model.string_type, {{"path", &model.string_type}});
        model.file_write_all_text = create_builtin(model.file_class,
                                                   "WriteAllText",
                                                   &model.void_type,
                                                   {{"path", &model.string_type}, {"content", &model.string_type}});
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
                if (model.classes_by_full_name.count(full_name) > 0 ||
                    model.enums_by_full_name.count(full_name) > 0) {
                    diagnostics_.add(unit.file, class_syntax->line, class_syntax->column,
                                     "Duplicate type declaration for '" + full_name + "'");
                    continue;
                }

                auto symbol = std::make_unique<ClassSymbol>();
                symbol->kind = class_syntax->kind == TypeDeclarationKind::Class
                                   ? TypeKind::Class
                                   : (class_syntax->kind == TypeDeclarationKind::Struct ? TypeKind::Struct : TypeKind::Interface);
                symbol->namespace_name = class_syntax->namespace_name;
                symbol->name = class_syntax->name;
                symbol->full_name = full_name;
                symbol->source_file = unit.file;
                symbol->syntax = class_syntax.get();
                symbol->using_namespaces = using_namespaces;
                for (const auto& type_parameter_name : class_syntax->type_parameters) {
                    auto type_parameter = std::make_unique<TypeSymbol>();
                    type_parameter->kind = TypeKind::TypeParameter;
                    type_parameter->display_name = type_parameter_name;
                    type_parameter->type_parameter_symbol = type_parameter.get();
                    const TypeSymbol* raw = type_parameter.get();
                    model.owned_types.push_back(std::move(type_parameter));
                    symbol->type_parameters.push_back(raw);
                }
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

            for (const auto& enum_syntax : unit.enums) {
                const string full_name = enum_syntax->namespace_name.empty()
                                             ? enum_syntax->name
                                             : enum_syntax->namespace_name + "." + enum_syntax->name;
                if (model.classes_by_full_name.count(full_name) > 0 ||
                    model.enums_by_full_name.count(full_name) > 0) {
                    diagnostics_.add(unit.file, enum_syntax->line, enum_syntax->column,
                                     "Duplicate type declaration for '" + full_name + "'");
                    continue;
                }

                auto symbol = std::make_unique<EnumSymbol>();
                symbol->namespace_name = enum_syntax->namespace_name;
                symbol->name = enum_syntax->name;
                symbol->full_name = full_name;
                symbol->source_file = unit.file;
                symbol->accessibility = accessibility_from_modifiers(enum_syntax->modifiers);
                symbol->syntax = enum_syntax.get();
                auto* raw = symbol.get();
                model.enums_by_full_name[full_name] = raw;
                model.enums.push_back(std::move(symbol));

                if (!enum_syntax->namespace_name.empty()) {
                    vector<string> parts;
                    std::stringstream stream(enum_syntax->namespace_name);
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
                    model.classes_by_full_name.count(directive.namespace_name) == 0 &&
                    model.enums_by_full_name.count(directive.namespace_name) == 0) {
                    diagnostics_.add(unit.file, directive.line, directive.column,
                                     "Unresolved using directive '" + directive.namespace_name + "'");
                }
            }
        }
    }

    void resolve_base_classes(SemanticModel& model) {
        for (const auto& class_holder : model.classes) {
            ClassSymbol* klass = class_holder.get();
            if (klass->is_builtin || klass->syntax == nullptr || klass->syntax->base_types.empty()) {
                continue;
            }

            for (const auto& base_syntax : klass->syntax->base_types) {
                const TypeSymbol* base_type = resolve_type_in_context(model,
                                                                      diagnostics_,
                                                                      klass->source_file,
                                                                      base_syntax,
                                                                      klass->namespace_name,
                                                                      klass->using_namespaces);
                if (base_type == &model.error_type) {
                    continue;
                }
                if (base_type->kind == TypeKind::Interface && base_type->class_symbol != nullptr) {
                    klass->interfaces.push_back(base_type->class_symbol);
                    klass->interface_types.push_back(base_type);
                    continue;
                }

                if (klass->kind == TypeKind::Class) {
                    if (klass->base_class != nullptr) {
                        diagnostics_.add(klass->source_file,
                                         base_syntax.line,
                                         base_syntax.column,
                                         "Class '" + klass->full_name + "' can only declare one base class");
                        continue;
                    }
                    if (base_type->kind != TypeKind::Class || base_type->class_symbol == nullptr || base_type->class_symbol->is_builtin) {
                        diagnostics_.add(klass->source_file,
                                         base_syntax.line,
                                         base_syntax.column,
                                         "Class '" + klass->full_name + "' can only inherit from a non-builtin class");
                        continue;
                    }
                    if (base_type->class_symbol == klass) {
                        diagnostics_.add(klass->source_file,
                                         base_syntax.line,
                                         base_syntax.column,
                                         "Class '" + klass->full_name + "' cannot inherit from itself");
                        continue;
                    }
                    klass->base_class = base_type->class_symbol;
                    continue;
                }

                diagnostics_.add(klass->source_file,
                                 base_syntax.line,
                                 base_syntax.column,
                                 "Only classes may declare a class base type");
            }
        }
    }

    void validate_inheritance_cycles(SemanticModel& model) {
        for (const auto& class_holder : model.classes) {
            ClassSymbol* klass = class_holder.get();
            if (klass->is_builtin || klass->base_class == nullptr || klass->syntax == nullptr) {
                continue;
            }

            std::unordered_set<const ClassSymbol*> seen;
            for (const ClassSymbol* current = klass; current != nullptr; current = current->base_class) {
                if (!seen.insert(current).second) {
                    diagnostics_.add(klass->source_file,
                                     klass->syntax->line,
                                     klass->syntax->column,
                                     "Inheritance cycle detected for class '" + klass->full_name + "'");
                    klass->base_class = nullptr;
                    break;
                }
            }
        }
    }

    void declare_enum_members(SemanticModel& model) {
        for (const auto& enum_holder : model.enums) {
            EnumSymbol* enum_symbol = enum_holder.get();
            if (enum_symbol->syntax == nullptr) {
                continue;
            }

            std::unordered_set<string> member_names;
            int64_t next_value = 0;
            for (const auto& member : enum_symbol->syntax->members) {
                if (!member_names.insert(member.name).second) {
                    diagnostics_.add(enum_symbol->source_file,
                                     member.line,
                                     member.column,
                                     "Duplicate enum member '" + member.name + "' in enum '" + enum_symbol->full_name + "'");
                    continue;
                }

                auto symbol = std::make_unique<EnumMemberSymbol>();
                symbol->name = member.name;
                symbol->value = next_value++;
                symbol->owner = enum_symbol;
                enum_symbol->members.push_back(std::move(symbol));
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
            std::unordered_map<string, const TypeSymbol*> type_parameter_bindings;
            for (std::size_t index = 0; index < klass->syntax->type_parameters.size() &&
                                        index < klass->type_parameters.size();
                 ++index) {
                type_parameter_bindings[klass->syntax->type_parameters[index]] = klass->type_parameters[index];
            }

            for (const auto& member : klass->syntax->members) {
                if (const auto* field = dynamic_cast<FieldDeclarationSyntax*>(member.get())) {
                    if (klass->kind == TypeKind::Interface) {
                        diagnostics_.add(klass->source_file, field->line, field->column,
                                         "Interfaces cannot declare fields");
                        continue;
                    }
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
                                                           klass->using_namespaces,
                                                           &type_parameter_bindings);
                    symbol->is_static = has_modifier(field->modifiers, ModifierKind::Static);
                    symbol->accessibility = accessibility_from_modifiers(field->modifiers);
                    symbol->slot = static_cast<int>(klass->fields.size());
                    symbol->owner = klass;
                    symbol->syntax = field;
                    klass->fields.push_back(std::move(symbol));
                    continue;
                }

                if (const auto* method = dynamic_cast<MethodDeclarationSyntax*>(member.get())) {
                    auto symbol = std::make_unique<MethodSymbol>();
                    symbol->name = method->name;
                    std::unordered_map<string, const TypeSymbol*> combined_bindings = type_parameter_bindings;
                    for (const auto& method_type_parameter_name : method->type_parameters) {
                        auto type_parameter = std::make_unique<TypeSymbol>();
                        type_parameter->kind = TypeKind::TypeParameter;
                        type_parameter->display_name = method_type_parameter_name;
                        type_parameter->type_parameter_symbol = type_parameter.get();
                        const TypeSymbol* raw = type_parameter.get();
                        model.owned_types.push_back(std::move(type_parameter));
                        symbol->type_parameters.push_back(raw);
                        combined_bindings[method_type_parameter_name] = raw;
                    }
                    symbol->return_type = resolve_type_in_context(model,
                                                                  diagnostics_,
                                                                  klass->source_file,
                                                                  method->return_type,
                                                                  klass->namespace_name,
                                                                  klass->using_namespaces,
                                                                  &combined_bindings);
                    symbol->is_static = has_modifier(method->modifiers, ModifierKind::Static);
                    symbol->is_virtual = has_modifier(method->modifiers, ModifierKind::Virtual);
                    symbol->is_override = has_modifier(method->modifiers, ModifierKind::Override);
                    symbol->accessibility =
                        klass->kind == TypeKind::Interface ? Accessibility::Public : accessibility_from_modifiers(method->modifiers);
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
                                                    klass->using_namespaces,
                                                    &combined_bindings),
                            static_cast<int>(index)});
                    }
                    const string signature = member_signature_key(method->name, symbol->is_static, symbol->parameters);
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
                    if (klass->kind == TypeKind::Interface) {
                        diagnostics_.add(klass->source_file, constructor->line, constructor->column,
                                         "Interfaces cannot declare constructors");
                        continue;
                    }
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
                                                    klass->using_namespaces,
                                                    &type_parameter_bindings),
                            static_cast<int>(index)});
                    }
                    std::ostringstream signature_builder;
                    signature_builder << "ctor";
                    for (const auto& parameter : symbol->parameters) {
                        signature_builder << "#" << parameter.type->display_name;
                    }
                    const string signature = signature_builder.str();
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

    void validate_inherited_members(SemanticModel& model) {
        for (const auto& class_holder : model.classes) {
            ClassSymbol* klass = class_holder.get();
            if (klass->is_builtin || klass->syntax == nullptr || klass->kind != TypeKind::Class) {
                continue;
            }

            for (const auto& field : klass->fields) {
                for (auto base = klass->base_class; base != nullptr; base = base->base_class) {
                    bool conflict_found = false;
                    for (const auto& base_field : base->fields) {
                        if (!is_inherited_accessible(base_field->accessibility) || base_field->name != field->name) {
                            continue;
                        }
                        diagnostics_.add(klass->source_file,
                                         field->syntax != nullptr ? field->syntax->line : klass->syntax->line,
                                         field->syntax != nullptr ? field->syntax->column : klass->syntax->column,
                                         "Field '" + field->name + "' in class '" + klass->full_name +
                                             "' conflicts with inherited field from '" + base->full_name + "'");
                        conflict_found = true;
                        break;
                    }
                    if (conflict_found) {
                        break;
                    }
                }
            }

            for (const auto& method : klass->methods) {
                const string signature = member_signature_key(method->name, method->is_static, method->parameters);
                if (method->is_virtual && method->is_static) {
                    diagnostics_.add(klass->source_file,
                                     method->syntax != nullptr ? method->syntax->line : klass->syntax->line,
                                     method->syntax != nullptr ? method->syntax->column : klass->syntax->column,
                                     "Static methods cannot be marked virtual");
                }

                if (method->is_override && method->is_static) {
                    diagnostics_.add(klass->source_file,
                                     method->syntax != nullptr ? method->syntax->line : klass->syntax->line,
                                     method->syntax != nullptr ? method->syntax->column : klass->syntax->column,
                                     "Static methods cannot be marked override");
                }

                bool matched_base_method = false;
                for (auto base = klass->base_class; base != nullptr; base = base->base_class) {
                    bool conflict_found = false;
                    for (const auto& base_method : base->methods) {
                        if (!is_inherited_accessible(base_method->accessibility)) {
                            continue;
                        }
                        if (member_signature_key(base_method->name, base_method->is_static, base_method->parameters) != signature) {
                            continue;
                        }
                        matched_base_method = true;
                        if (method->is_override) {
                            if (base_method->virtual_root == nullptr && !base_method->is_virtual) {
                                diagnostics_.add(klass->source_file,
                                                 method->syntax != nullptr ? method->syntax->line : klass->syntax->line,
                                                 method->syntax != nullptr ? method->syntax->column : klass->syntax->column,
                                                 "Method '" + method->name + "' cannot override non-virtual base method from '" +
                                                     base->full_name + "'");
                            } else if (!are_types_equal(method->return_type, base_method->return_type)) {
                                diagnostics_.add(klass->source_file,
                                                 method->syntax != nullptr ? method->syntax->line : klass->syntax->line,
                                                 method->syntax != nullptr ? method->syntax->column : klass->syntax->column,
                                                 "Override '" + method->name + "' must match the base return type");
                            } else {
                                method->overridden_method = base_method.get();
                                method->virtual_root =
                                    base_method->virtual_root != nullptr ? base_method->virtual_root : base_method.get();
                                method->virtual_slot =
                                    method->virtual_root != nullptr ? method->virtual_root->slot : base_method->slot;
                            }
                        } else {
                            diagnostics_.add(klass->source_file,
                                             method->syntax != nullptr ? method->syntax->line : klass->syntax->line,
                                             method->syntax != nullptr ? method->syntax->column : klass->syntax->column,
                                             "Method '" + method->name + "' in class '" + klass->full_name +
                                                 "' conflicts with inherited method from '" + base->full_name +
                                                 "'; use 'override' for virtual members");
                        }
                        conflict_found = true;
                        break;
                    }
                    if (conflict_found) {
                        break;
                    }
                }

                if (!matched_base_method && method->is_override) {
                    diagnostics_.add(klass->source_file,
                                     method->syntax != nullptr ? method->syntax->line : klass->syntax->line,
                                     method->syntax != nullptr ? method->syntax->column : klass->syntax->column,
                                     "Method '" + method->name + "' is marked override but no matching base method was found");
                }

                if (!method->is_override && method->is_virtual) {
                    method->virtual_root = method.get();
                    method->virtual_slot = method->slot;
                }
            }
        }
    }

    void collect_interface_methods(const ClassSymbol& interface_symbol,
                                   std::vector<const MethodSymbol*>& methods,
                                   std::unordered_set<string>& seen_signatures) {
        for (const auto& base_interface : interface_symbol.interfaces) {
            collect_interface_methods(*base_interface, methods, seen_signatures);
        }
        for (const auto& method : interface_symbol.methods) {
            const string signature = member_signature_key(method->name, method->is_static, method->parameters);
            if (seen_signatures.insert(signature).second) {
                methods.push_back(method.get());
            }
        }
    }

    void validate_interface_implementations(SemanticModel& model) {
        for (const auto& class_holder : model.classes) {
            ClassSymbol* klass = class_holder.get();
            if (klass->is_builtin || (klass->kind != TypeKind::Class && klass->kind != TypeKind::Struct)) {
                continue;
            }

            std::unordered_set<string> seen_interfaces;
            std::vector<const TypeSymbol*> worklist = klass->interface_types;
            if (klass->base_class != nullptr) {
                for (const auto* inherited_interface : klass->base_class->interface_types) {
                    worklist.push_back(inherited_interface);
                }
            }

            while (!worklist.empty()) {
                const TypeSymbol* interface_type = worklist.back();
                worklist.pop_back();
                if (interface_type == nullptr || interface_type->kind != TypeKind::Interface ||
                    interface_type->class_symbol == nullptr ||
                    !seen_interfaces.insert(interface_type->display_name).second) {
                    continue;
                }
                const ClassSymbol* interface_symbol = interface_type->class_symbol;

                for (const auto* parent_interface : interface_symbol->interfaces) {
                    auto inherited_interface_type = std::make_unique<TypeSymbol>();
                    inherited_interface_type->kind = parent_interface->kind;
                    inherited_interface_type->display_name = parent_interface->full_name;
                    inherited_interface_type->class_symbol = parent_interface;
                    const TypeSymbol* raw = inherited_interface_type.get();
                    model.owned_types.push_back(std::move(inherited_interface_type));
                    worklist.push_back(raw);
                }

                std::vector<const MethodSymbol*> required_methods;
                std::unordered_set<string> seen_signatures;
                collect_interface_methods(*interface_symbol, required_methods, seen_signatures);
                std::unordered_map<const TypeSymbol*, const TypeSymbol*> substitutions;
                for (std::size_t index = 0; index < interface_symbol->type_parameters.size() &&
                                            index < interface_type->type_arguments.size();
                     ++index) {
                    substitutions[interface_symbol->type_parameters[index]] = interface_type->type_arguments[index];
                }
                for (const auto* required_method : required_methods) {
                    const MethodSymbol* implementation = nullptr;
                    for (const ClassSymbol* current = klass; current != nullptr && implementation == nullptr;
                         current = current->base_class) {
                        for (const auto& method : current->methods) {
                            if (!method->is_static && method->name == required_method->name) {
                                implementation = method.get();
                                break;
                            }
                        }
                    }
                    vector<ParameterSymbol> substituted_parameters;
                    for (const auto& parameter : required_method->parameters) {
                        substituted_parameters.push_back(ParameterSymbol{
                            parameter.name,
                            substitute_type(model, parameter.type, substitutions),
                            parameter.index});
                    }
                    const TypeSymbol* substituted_return_type =
                        substitute_type(model, required_method->return_type, substitutions);
                    if (implementation == nullptr ||
                        member_signature_key(implementation->name, implementation->is_static, implementation->parameters) !=
                            member_signature_key(required_method->name, required_method->is_static, substituted_parameters) ||
                        !is_type_assignable(substituted_return_type, implementation->return_type)) {
                        diagnostics_.add(klass->source_file,
                                         klass->syntax != nullptr ? klass->syntax->line : 1,
                                         klass->syntax != nullptr ? klass->syntax->column : 1,
                                         "Type '" + klass->full_name + "' does not implement interface member '" +
                                             interface_type->display_name + "." + required_method->name + "'");
                    }
                }
            }
        }
    }

    void validate_base_constructors(SemanticModel& model) {
        for (const auto& class_holder : model.classes) {
            ClassSymbol* klass = class_holder.get();
            if (klass->is_builtin || klass->kind != TypeKind::Class || klass->base_class == nullptr || klass->syntax == nullptr) {
                continue;
            }

            const ClassSymbol* base = klass->base_class;
            if (base->constructors.empty()) {
                continue;
            }

            bool has_accessible_parameterless = false;
            for (const auto& constructor : base->constructors) {
                if (!constructor->parameters.empty()) {
                    continue;
                }
                if (is_accessible_from(constructor->accessibility, *constructor->owner, *klass)) {
                    has_accessible_parameterless = true;
                    break;
                }
            }

            for (const auto& constructor : klass->constructors) {
                const bool has_explicit_base_call =
                    constructor->syntax != nullptr && constructor->syntax->has_base_initializer;
                if (!has_explicit_base_call && !has_accessible_parameterless) {
                    diagnostics_.add(klass->source_file,
                                     constructor->syntax != nullptr ? constructor->syntax->line : klass->syntax->line,
                                     constructor->syntax != nullptr ? constructor->syntax->column : klass->syntax->column,
                                     "Base class '" + base->full_name + "' must have an accessible parameterless constructor");
                }
            }

            if (klass->constructors.empty() && !has_accessible_parameterless) {
                diagnostics_.add(klass->source_file,
                                 klass->syntax->line,
                                 klass->syntax->column,
                                 "Base class '" + base->full_name + "' must have an accessible parameterless constructor");
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
        const TypeSymbol* type_symbol = nullptr;
        std::unique_ptr<BoundExpression> value;
        vector<const MethodSymbol*> methods;
        std::unique_ptr<BoundExpression> receiver;
        bool via_base = false;
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
            if (constructor.owner != nullptr &&
                constructor.owner->kind == TypeKind::Class &&
                constructor.owner->base_class != nullptr &&
                constructor.syntax != nullptr &&
                constructor.syntax->has_base_initializer) {
                vector<const TypeSymbol*> argument_types;
                for (const auto& argument : constructor.syntax->base_arguments) {
                    auto bound_argument = bind_expression(*argument);
                    argument_types.push_back(bound_argument->type);
                    body->base_arguments.push_back(std::move(bound_argument));
                }

                bool ambiguous = false;
                const ConstructorSymbol* inaccessible_match = nullptr;
                body->base_constructor = select_best_constructor_overload(*constructor.owner->base_class,
                                                                         argument_types,
                                                                         &ambiguous,
                                                                         &inaccessible_match);
                if (ambiguous) {
                    diagnostics_.add(find_file_for_class(&current_class_),
                                     constructor.syntax->line,
                                     constructor.syntax->column,
                                     "Base constructor call is ambiguous");
                } else if (body->base_constructor == nullptr && inaccessible_match != nullptr) {
                    report_inaccessible(constructor.owner->base_class->name,
                                        inaccessible_match->accessibility,
                                        *inaccessible_match->owner,
                                        constructor.syntax->line,
                                        constructor.syntax->column);
                } else if (body->base_constructor == nullptr) {
                    diagnostics_.add(find_file_for_class(&current_class_),
                                     constructor.syntax->line,
                                     constructor.syntax->column,
                                     "No matching base constructor was found");
                } else {
                    for (std::size_t index = 0; index < body->base_arguments.size(); ++index) {
                        body->base_arguments[index] =
                            convert_expression(body->base_constructor->parameters[index].type,
                                               std::move(body->base_arguments[index]));
                    }
                }
            }
            body->body = bind_block(*constructor.syntax->body);
            body->locals = std::move(locals_);
            pop_scope();
            return body;
        }

    private:
        const TypeSymbol* make_named_type(const ClassSymbol& klass) {
            auto type_symbol = std::make_unique<TypeSymbol>();
            type_symbol->kind = klass.kind;
            type_symbol->display_name = klass.full_name;
            type_symbol->class_symbol = &klass;
            auto* raw = type_symbol.get();
            program_.semantic_model.owned_types.push_back(std::move(type_symbol));
            return raw;
        }

        const TypeSymbol* make_named_type(const EnumSymbol& enum_symbol) {
            auto type_symbol = std::make_unique<TypeSymbol>();
            type_symbol->kind = TypeKind::Enum;
            type_symbol->display_name = enum_symbol.full_name;
            type_symbol->enum_symbol = &enum_symbol;
            auto* raw = type_symbol.get();
            program_.semantic_model.owned_types.push_back(std::move(type_symbol));
            return raw;
        }

        std::unordered_map<const TypeSymbol*, const TypeSymbol*> build_type_substitutions(const TypeSymbol* type) {
            std::unordered_map<const TypeSymbol*, const TypeSymbol*> substitutions;
            if (type == nullptr || type->class_symbol == nullptr) {
                return substitutions;
            }
            for (std::size_t index = 0; index < type->class_symbol->type_parameters.size() &&
                                        index < type->type_arguments.size();
                 ++index) {
                substitutions[type->class_symbol->type_parameters[index]] = type->type_arguments[index];
            }
            return substitutions;
        }

        bool infer_method_type_arguments(const TypeSymbol* parameter_type,
                                         const TypeSymbol* argument_type,
                                         std::unordered_map<const TypeSymbol*, const TypeSymbol*>& substitutions) {
            if (parameter_type == nullptr || argument_type == nullptr) {
                return false;
            }
            if (parameter_type->kind == TypeKind::TypeParameter) {
                const TypeSymbol* key =
                    parameter_type->type_parameter_symbol != nullptr ? parameter_type->type_parameter_symbol : parameter_type;
                const auto found = substitutions.find(key);
                if (found == substitutions.end()) {
                    substitutions[key] = argument_type;
                    return true;
                }
                return are_types_equal(found->second, argument_type);
            }
            if (parameter_type->kind == TypeKind::Array && argument_type->kind == TypeKind::Array) {
                return infer_method_type_arguments(parameter_type->element_type, argument_type->element_type, substitutions);
            }
            return are_types_equal(parameter_type, argument_type);
        }

        const MethodSymbol* specialize_method(const MethodSymbol& method,
                                              const std::unordered_map<const TypeSymbol*, const TypeSymbol*>& substitutions) {
            bool changed = false;
            auto specialized = std::make_unique<MethodSymbol>(method);
            specialized->generic_definition = method.generic_definition != nullptr ? method.generic_definition : &method;
            specialized->parameters.clear();
            specialized->type_parameters.clear();
            specialized->return_type = substitute_type(program_.semantic_model, method.return_type, substitutions);
            changed = changed || specialized->return_type != method.return_type;
            for (const auto& parameter : method.parameters) {
                const TypeSymbol* substituted_type = substitute_type(program_.semantic_model, parameter.type, substitutions);
                changed = changed || substituted_type != parameter.type;
                specialized->parameters.push_back(ParameterSymbol{parameter.name, substituted_type, parameter.index});
            }
            if (!changed) {
                return &method;
            }
            const MethodSymbol* raw = specialized.get();
            program_.semantic_model.owned_method_specializations.push_back(std::move(specialized));
            return raw;
        }

        const ConstructorSymbol* specialize_constructor(
            const ConstructorSymbol& constructor,
            const std::unordered_map<const TypeSymbol*, const TypeSymbol*>& substitutions) {
            bool changed = false;
            auto specialized = std::make_unique<ConstructorSymbol>(constructor);
            specialized->parameters.clear();
            for (const auto& parameter : constructor.parameters) {
                const TypeSymbol* substituted_type = substitute_type(program_.semantic_model, parameter.type, substitutions);
                changed = changed || substituted_type != parameter.type;
                specialized->parameters.push_back(ParameterSymbol{parameter.name, substituted_type, parameter.index});
            }
            if (!changed) {
                return &constructor;
            }
            const ConstructorSymbol* raw = specialized.get();
            program_.semantic_model.owned_constructor_specializations.push_back(std::move(specialized));
            return raw;
        }

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
            this_type->kind = current_class_.kind;
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
            const TypeSymbol* field_type = field->type;
            if (receiver != nullptr && receiver->type != nullptr) {
                field_type = substitute_type(program_.semantic_model, field->type, build_type_substitutions(receiver->type));
            }
            if (!field->is_static && receiver != nullptr && receiver->type != nullptr &&
                receiver->type->kind == TypeKind::Class && receiver->type->class_symbol != field->owner) {
                receiver = convert_expression(make_named_type(*field->owner), std::move(receiver));
            }
            auto field_expression = std::make_unique<BoundFieldExpression>();
            field_expression->kind = BoundExpressionKind::Field;
            field_expression->type = field_type;
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

        const FieldSymbol* find_matching_field(const ClassSymbol& klass,
                                               const string& name,
                                               bool require_static) const {
            for (auto current = &klass; current != nullptr; current = current->base_class) {
                for (const auto& field : current->fields) {
                    if (field->name == name && field->is_static == require_static) {
                        return field.get();
                    }
                }
            }
            return nullptr;
        }

        const MethodSymbol* find_matching_method(const ClassSymbol& klass,
                                                 const string& name,
                                                 bool require_static) const {
            for (auto current = &klass; current != nullptr; current = current->base_class) {
                for (const auto& method : current->methods) {
                    if (method->name == name && method->is_static == require_static) {
                        return method.get();
                    }
                }
                if (current->kind == TypeKind::Interface) {
                    for (const auto* interface_symbol : current->interfaces) {
                        if (const auto* found = find_matching_method(*interface_symbol, name, require_static)) {
                            return found;
                        }
                    }
                }
            }
            return nullptr;
        }

        const FieldSymbol* select_field(const ClassSymbol& klass,
                                        const string& name,
                                        bool require_static,
                                        bool* found_inaccessible = nullptr) const {
            for (auto current = &klass; current != nullptr; current = current->base_class) {
                for (const auto& field : current->fields) {
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
            }
            return nullptr;
        }

        vector<const MethodSymbol*> select_methods(const ClassSymbol& klass,
                                                   const string& name,
                                                   bool require_static,
                                                   bool* found_inaccessible = nullptr) const {
            vector<const MethodSymbol*> methods;
            for (auto current = &klass; current != nullptr; current = current->base_class) {
                for (const auto& method : current->methods) {
                    if (method->name != name || method->is_static != require_static) {
                        continue;
                    }
                    if (is_accessible(*method)) {
                        methods.push_back(method.get());
                    } else if (found_inaccessible != nullptr) {
                        *found_inaccessible = true;
                    }
                }
                if (current->kind == TypeKind::Interface) {
                    for (const auto* interface_symbol : current->interfaces) {
                        auto inherited_methods = select_methods(*interface_symbol, name, require_static, found_inaccessible);
                        methods.insert(methods.end(), inherited_methods.begin(), inherited_methods.end());
                    }
                }
            }
            return methods;
        }

        const EnumMemberSymbol* select_enum_member(const EnumSymbol& enum_symbol, const string& name) const {
            for (const auto& member : enum_symbol.members) {
                if (member->name == name) {
                    return member.get();
                }
            }
            return nullptr;
        }

        int parameter_match_score(const TypeSymbol* parameter_type,
                                  const TypeSymbol* argument_type,
                                  bool allow_console_enum_print = false) const {
            if (are_types_equal(parameter_type, argument_type)) {
                return 3;
            }
            if (allow_console_enum_print &&
                parameter_type == &program_.semantic_model.int_type &&
                argument_type != nullptr &&
                argument_type->kind == TypeKind::Enum) {
                return 2;
            }
            if (is_type_assignable(parameter_type, argument_type)) {
                return 1;
            }
            return -1;
        }

        const MethodSymbol* select_best_method_overload(const vector<const MethodSymbol*>& candidates,
                                                        const vector<const TypeSymbol*>& argument_types,
                                                        bool* ambiguous) const {
            const MethodSymbol* selected = nullptr;
            int best_score = -1;
            *ambiguous = false;
            for (const auto* candidate : candidates) {
                if (candidate->parameters.size() != argument_types.size()) {
                    continue;
                }

                const bool allow_console_enum_print =
                    candidate->owner == program_.semantic_model.console_class &&
                    (candidate->name == "Write" || candidate->name == "WriteLine");
                int total_score = 0;
                bool compatible = true;
                for (std::size_t index = 0; index < argument_types.size(); ++index) {
                    const int score =
                        parameter_match_score(candidate->parameters[index].type, argument_types[index], allow_console_enum_print);
                    if (score < 0) {
                        compatible = false;
                        break;
                    }
                    total_score += score;
                }
                if (!compatible) {
                    continue;
                }
                if (total_score > best_score) {
                    best_score = total_score;
                    selected = candidate;
                    *ambiguous = false;
                } else if (total_score == best_score) {
                    *ambiguous = true;
                }
            }
            if (*ambiguous) {
                return nullptr;
            }
            return selected;
        }

        const ConstructorSymbol* select_best_constructor_overload(const ClassSymbol& klass,
                                                                  const vector<const TypeSymbol*>& argument_types,
                                                                  bool* ambiguous,
                                                                  const ConstructorSymbol** inaccessible_match) const {
            const ConstructorSymbol* selected = nullptr;
            int best_score = -1;
            *ambiguous = false;
            *inaccessible_match = nullptr;
            for (const auto& constructor : klass.constructors) {
                if (constructor->parameters.size() != argument_types.size()) {
                    continue;
                }

                int total_score = 0;
                bool compatible = true;
                for (std::size_t index = 0; index < argument_types.size(); ++index) {
                    const int score = parameter_match_score(constructor->parameters[index].type, argument_types[index]);
                    if (score < 0) {
                        compatible = false;
                        break;
                    }
                    total_score += score;
                }
                if (!compatible) {
                    continue;
                }

                if (!is_accessible(*constructor)) {
                    *inaccessible_match = constructor.get();
                    continue;
                }

                if (total_score > best_score) {
                    best_score = total_score;
                    selected = constructor.get();
                    *ambiguous = false;
                } else if (total_score == best_score) {
                    *ambiguous = true;
                }
            }
            if (*ambiguous) {
                return nullptr;
            }
            return selected;
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

        std::unique_ptr<BoundExpression> convert_expression(const TypeSymbol* destination,
                                                            std::unique_ptr<BoundExpression> expression) {
            if (destination == nullptr || expression == nullptr || expression->type == nullptr ||
                expression->type == &program_.semantic_model.error_type || are_types_equal(destination, expression->type)) {
                return expression;
            }
            if ((destination->kind == TypeKind::Class || destination->kind == TypeKind::Interface) &&
                (expression->type->kind == TypeKind::Class ||
                 expression->type->kind == TypeKind::Struct ||
                 expression->type->kind == TypeKind::Interface) &&
                expression->type->class_symbol != nullptr &&
                destination->class_symbol != nullptr &&
                is_type_assignable(destination, expression->type)) {
                auto conversion = std::make_unique<BoundConversionExpression>();
                conversion->kind = BoundExpressionKind::Conversion;
                conversion->type = destination;
                conversion->line = expression->line;
                conversion->column = expression->column;
                conversion->expression = std::move(expression);
                return conversion;
            }
            return expression;
        }

        void harmonize_class_operands(std::unique_ptr<BoundExpression>& left, std::unique_ptr<BoundExpression>& right) {
            if (left == nullptr || right == nullptr || left->type == nullptr || right->type == nullptr) {
                return;
            }
            const bool left_named = left->type->kind == TypeKind::Class || left->type->kind == TypeKind::Interface;
            const bool right_named = right->type->kind == TypeKind::Class || right->type->kind == TypeKind::Interface;
            if (!left_named || !right_named || are_types_equal(left->type, right->type)) {
                return;
            }
            if (is_type_assignable(left->type, right->type)) {
                right = convert_expression(left->type, std::move(right));
                return;
            }
            if (is_type_assignable(right->type, left->type)) {
                left = convert_expression(right->type, std::move(left));
            }
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
                const TypeSymbol* type = nullptr;
                if (scopes_.back().count(variable->name) > 0) {
                    diagnostics_.add(find_file_for_class(&current_class_), variable->line, variable->column,
                                     "Local variable '" + variable->name + "' is already declared in this scope");
                }
                if (variable->initializer != nullptr) {
                    bound->initializer = bind_expression(*variable->initializer);
                }

                if (variable->type.is_var) {
                    if (bound->initializer == nullptr) {
                        diagnostics_.add(find_file_for_class(&current_class_), variable->line, variable->column,
                                         "'var' declarations require an initializer");
                        type = &program_.semantic_model.error_type;
                    } else if (bound->initializer->type == &program_.semantic_model.null_type ||
                               bound->initializer->type == &program_.semantic_model.void_type) {
                        diagnostics_.add(find_file_for_class(&current_class_), variable->line, variable->column,
                                         "Cannot infer a local type from this initializer");
                        type = &program_.semantic_model.error_type;
                    } else {
                        type = bound->initializer->type;
                    }
                } else {
                    type = resolve_type(variable->type);
                }

                bound->variable = declare_local(variable->name, type);
                if (bound->initializer != nullptr) {
                    if (!is_type_assignable(type, bound->initializer->type)) {
                        diagnostics_.add(find_file_for_class(&current_class_), variable->line, variable->column,
                                         "Cannot assign expression of type '" + bound->initializer->type->display_name +
                                             "' to variable of type '" + type->display_name + "'");
                    } else {
                        bound->initializer = convert_expression(type, std::move(bound->initializer));
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
                ++loop_depth_;
                bound->body = bind_statement(*while_statement->body);
                --loop_depth_;
                return bound;
            }
            if (const auto* for_statement = dynamic_cast<const ForStatementSyntax*>(&statement)) {
                auto bound = std::make_unique<BoundForStatement>();
                bound->kind = BoundStatementKind::For;
                bound->line = for_statement->line;
                bound->column = for_statement->column;
                push_scope();
                if (for_statement->initializer != nullptr) {
                    bound->initializer = bind_statement(*for_statement->initializer);
                }
                if (for_statement->condition != nullptr) {
                    bound->condition = bind_expression(*for_statement->condition);
                    if (bound->condition->type != &program_.semantic_model.bool_type) {
                        diagnostics_.add(find_file_for_class(&current_class_), for_statement->line, for_statement->column,
                                         "For condition must be of type 'bool'");
                    }
                }
                if (for_statement->update != nullptr) {
                    bound->update = bind_expression(*for_statement->update);
                }
                ++loop_depth_;
                bound->body = bind_statement(*for_statement->body);
                --loop_depth_;
                pop_scope();
                return bound;
            }
            if (const auto* break_statement = dynamic_cast<const BreakStatementSyntax*>(&statement)) {
                auto bound = std::make_unique<BoundBreakStatement>();
                bound->kind = BoundStatementKind::Break;
                bound->line = break_statement->line;
                bound->column = break_statement->column;
                if (loop_depth_ == 0) {
                    diagnostics_.add(find_file_for_class(&current_class_), break_statement->line, break_statement->column,
                                     "'break' can only be used inside a loop");
                }
                return bound;
            }
            if (const auto* continue_statement = dynamic_cast<const ContinueStatementSyntax*>(&statement)) {
                auto bound = std::make_unique<BoundContinueStatement>();
                bound->kind = BoundStatementKind::Continue;
                bound->line = continue_statement->line;
                bound->column = continue_statement->column;
                if (loop_depth_ == 0) {
                    diagnostics_.add(find_file_for_class(&current_class_), continue_statement->line, continue_statement->column,
                                     "'continue' can only be used inside a loop");
                }
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
                } else if (bound->expression != nullptr) {
                    bound->expression = convert_expression(expected, std::move(bound->expression));
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

            if (dynamic_cast<const BaseExpressionSyntax*>(&expression) != nullptr) {
                EntityResolution entity = bind_entity(expression);
                if (entity.kind == EntityResolution::Kind::Value && entity.value != nullptr) {
                    return std::move(entity.value);
                }
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
                } else {
                    value = convert_expression(target->type, std::move(value));
                }
                bound->type = target->type;
                bound->target = std::move(target);
                bound->expression = std::move(value);
                return bound;
            }

            if (const auto* access = dynamic_cast<const ElementAccessExpressionSyntax*>(&expression)) {
                return bind_element_access(*access);
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
                if (binary->op == TokenKind::EqualsEquals || binary->op == TokenKind::BangEquals) {
                    harmonize_class_operands(left, right);
                }
                auto bound = std::make_unique<BoundBinaryExpression>();
                bound->kind = BoundExpressionKind::Binary;
                bound->line = expression.line;
                bound->column = expression.column;
                bound->left = std::move(left);
                bound->right = std::move(right);
                bound->op = binary->op;
                switch (binary->op) {
                    case TokenKind::Plus:
                        if (bound->left->type == &program_.semantic_model.int_type &&
                            bound->right->type == &program_.semantic_model.int_type) {
                            bound->type = &program_.semantic_model.int_type;
                            break;
                        }
                        if (is_string_concatenation(program_.semantic_model, bound->left->type, bound->right->type)) {
                            bound->type = &program_.semantic_model.string_type;
                            break;
                        }
                        diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                         "Operator '+' requires int operands or string concatenation operands");
                        bound->type = &program_.semantic_model.error_type;
                        break;
                    case TokenKind::Minus:
                    case TokenKind::Star:
                    case TokenKind::Slash:
                    case TokenKind::Percent:
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
                        if (bound->left->type != nullptr &&
                            bound->right->type != nullptr &&
                            (bound->left->type->kind == TypeKind::Enum || bound->right->type->kind == TypeKind::Enum)) {
                            if (bound->left->type->kind != TypeKind::Enum ||
                                bound->right->type->kind != TypeKind::Enum ||
                                !are_types_equal(bound->left->type, bound->right->type)) {
                                diagnostics_.add(find_file_for_class(&current_class_),
                                                 expression.line,
                                                 expression.column,
                                                 "Enum equality requires operands of the same enum type");
                            }
                        } else if (!is_type_assignable(bound->left->type, bound->right->type) &&
                                   !is_type_assignable(bound->right->type, bound->left->type)) {
                            diagnostics_.add(find_file_for_class(&current_class_),
                                             expression.line,
                                             expression.column,
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

        std::unique_ptr<BoundExpression> bind_element_access(const ElementAccessExpressionSyntax& syntax) {
            auto target_expression = bind_expression(*syntax.target);
            auto index_expression = bind_expression(*syntax.index);
            if (index_expression->type != &program_.semantic_model.int_type) {
                diagnostics_.add(find_file_for_class(&current_class_), syntax.line, syntax.column,
                                 "Indices must be of type 'int'");
            }

            if (target_expression->type == &program_.semantic_model.string_type) {
                auto bound = std::make_unique<BoundStringIndexExpression>();
                bound->kind = BoundExpressionKind::StringIndex;
                bound->line = syntax.line;
                bound->column = syntax.column;
                bound->type = &program_.semantic_model.string_type;
                bound->string_expression = std::move(target_expression);
                bound->index_expression = std::move(index_expression);
                return bound;
            }

            auto bound = std::make_unique<BoundArrayIndexExpression>();
            bound->kind = BoundExpressionKind::ArrayIndex;
            bound->line = syntax.line;
            bound->column = syntax.column;
            bound->array_expression = std::move(target_expression);
            bound->index_expression = std::move(index_expression);

            if (bound->array_expression->type == nullptr || bound->array_expression->type->kind != TypeKind::Array ||
                bound->array_expression->type->element_type == nullptr) {
                diagnostics_.add(find_file_for_class(&current_class_), syntax.line, syntax.column,
                                 "Element access requires an array or string value");
                bound->type = &program_.semantic_model.error_type;
                return bound;
            }

            bound->type = bound->array_expression->type->element_type;
            return bound;
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

            bool ambiguous = false;
            vector<const MethodSymbol*> specialized_candidates;
            const TypeSymbol* receiver_or_type = entity.receiver != nullptr ? entity.receiver->type : entity.type_symbol;
            for (const auto* candidate : entity.methods) {
                auto substitutions = build_type_substitutions(receiver_or_type);
                bool inference_failed = false;
                if (!candidate->type_parameters.empty()) {
                    if (candidate->parameters.size() != argument_types.size()) {
                        continue;
                    }
                    for (std::size_t index = 0; index < candidate->parameters.size(); ++index) {
                        if (!infer_method_type_arguments(candidate->parameters[index].type, argument_types[index], substitutions)) {
                            inference_failed = true;
                            break;
                        }
                    }
                    if (inference_failed) {
                        continue;
                    }
                }
                specialized_candidates.push_back(specialize_method(*candidate, substitutions));
            }

            const MethodSymbol* selected = select_best_method_overload(specialized_candidates, argument_types, &ambiguous);

            if (ambiguous) {
                diagnostics_.add(find_file_for_class(&current_class_), syntax.line, syntax.column,
                                 "Call to '" + render_callee_name(*syntax.callee) + "' is ambiguous for the provided arguments");
                auto fallback = std::make_unique<BoundLiteralExpression>();
                fallback->kind = BoundExpressionKind::Literal;
                fallback->type = &program_.semantic_model.error_type;
                fallback->line = syntax.line;
                fallback->column = syntax.column;
                fallback->value = nullptr;
                return fallback;
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
            if (entity.receiver != nullptr && selected->owner != nullptr) {
                call->receiver = convert_expression(make_named_type(*selected->owner), std::move(entity.receiver));
            } else {
                call->receiver = std::move(entity.receiver);
            }
            for (std::size_t index = 0; index < arguments.size(); ++index) {
                call->arguments.push_back(convert_expression(selected->parameters[index].type, std::move(arguments[index])));
            }
            call->dispatch_interface =
                call->receiver != nullptr &&
                call->receiver->type != nullptr &&
                call->receiver->type->kind == TypeKind::Interface &&
                !selected->is_static;
            call->dispatch_virtual =
                !call->dispatch_interface &&
                !entity.via_base &&
                call->receiver != nullptr &&
                selected->virtual_root != nullptr &&
                !selected->is_static;
            if (call->dispatch_interface) {
                call->dispatch_type = call->receiver->type;
            } else if (call->dispatch_virtual && selected->virtual_root != nullptr) {
                call->dispatch_type = make_named_type(*selected->virtual_root->owner);
            }
            return call;
        }

        std::unique_ptr<BoundExpression> bind_object_creation(const ObjectCreationExpressionSyntax& syntax) {
            const TypeSymbol* type = resolve_type(syntax.type);
            if ((type->kind != TypeKind::Class && type->kind != TypeKind::Struct) || type->class_symbol == nullptr) {
                diagnostics_.add(find_file_for_class(&current_class_), syntax.line, syntax.column,
                                 "The 'new' operator requires a class or struct type");
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

            bool ambiguous = false;
            const ConstructorSymbol* inaccessible_match = nullptr;
            std::unordered_map<const TypeSymbol*, const TypeSymbol*> substitutions = build_type_substitutions(type);
            vector<const ConstructorSymbol*> specialized_candidates;
            for (const auto& constructor : type->class_symbol->constructors) {
                specialized_candidates.push_back(specialize_constructor(*constructor, substitutions));
            }
            const ConstructorSymbol* selected = nullptr;
            {
                int best_score = -1;
                ambiguous = false;
                inaccessible_match = nullptr;
                for (const auto* candidate : specialized_candidates) {
                    if (candidate->parameters.size() != argument_types.size()) {
                        continue;
                    }

                    int total_score = 0;
                    bool compatible = true;
                    for (std::size_t index = 0; index < argument_types.size(); ++index) {
                        const int score = parameter_match_score(candidate->parameters[index].type, argument_types[index]);
                        if (score < 0) {
                            compatible = false;
                            break;
                        }
                        total_score += score;
                    }
                    if (!compatible) {
                        continue;
                    }
                    if (!is_accessible(*candidate)) {
                        inaccessible_match = candidate;
                        continue;
                    }
                    if (total_score > best_score) {
                        best_score = total_score;
                        selected = candidate;
                        ambiguous = false;
                    } else if (total_score == best_score) {
                        ambiguous = true;
                    }
                }
                if (ambiguous) {
                    selected = nullptr;
                }
            }

            if (ambiguous) {
                diagnostics_.add(find_file_for_class(&current_class_), syntax.line, syntax.column,
                                 "Constructor call for '" + type->display_name + "' is ambiguous for the provided arguments");
            } else if (selected == nullptr && !type->class_symbol->constructors.empty() && inaccessible_match != nullptr) {
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
            bound->zero_initialize = type->kind == TypeKind::Struct && selected == nullptr && arguments.empty();
            if (selected != nullptr) {
                for (std::size_t index = 0; index < arguments.size(); ++index) {
                    bound->arguments.push_back(convert_expression(selected->parameters[index].type, std::move(arguments[index])));
                }
            } else {
                bound->arguments = std::move(arguments);
            }
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

                bool found_inaccessible_instance_field = false;
                if (!is_current_static_context()) {
                    if (const auto* field = select_field(current_class_, name->name, false, &found_inaccessible_instance_field)) {
                        EntityResolution result;
                        result.kind = EntityResolution::Kind::Value;
                        result.value = make_field_expression(make_this_expression(expression.line, expression.column),
                                                             field,
                                                             expression.line,
                                                             expression.column);
                        return result;
                    }
                }

                bool found_inaccessible_static_field = false;
                if (const auto* field = select_field(current_class_, name->name, true, &found_inaccessible_static_field)) {
                    EntityResolution result;
                    result.kind = EntityResolution::Kind::Value;
                    result.value = make_field_expression(nullptr, field, expression.line, expression.column);
                    return result;
                }

                if (found_inaccessible_instance_field) {
                    if (const auto* field = find_matching_field(current_class_, name->name, false)) {
                        report_inaccessible(name->name, field->accessibility, *field->owner, expression.line, expression.column);
                        return {};
                    }
                }

                if (found_inaccessible_static_field) {
                    if (const auto* field = find_matching_field(current_class_, name->name, true)) {
                        report_inaccessible(name->name, field->accessibility, *field->owner, expression.line, expression.column);
                        return {};
                    }
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
                        if (const auto* method = find_matching_method(current_class_, name->name, false)) {
                            report_inaccessible(name->name, method->accessibility, *method->owner, expression.line, expression.column);
                            return {};
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
                        if (const auto* method = find_matching_method(current_class_, name->name, true)) {
                            report_inaccessible(name->name, method->accessibility, *method->owner, expression.line, expression.column);
                            return {};
                        }
                    }
                }

                if (const ClassSymbol* type = resolve_class(name->name)) {
                    EntityResolution result;
                    result.kind = EntityResolution::Kind::Type;
                    result.type_symbol = make_named_type(*type);
                    return result;
                }

                if (const EnumSymbol* type = resolve_enum(name->name)) {
                    EntityResolution result;
                    result.kind = EntityResolution::Kind::Type;
                    result.type_symbol = make_named_type(*type);
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

            if (dynamic_cast<const BaseExpressionSyntax*>(&expression) != nullptr) {
                EntityResolution result;
                if (is_current_static_context()) {
                    diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                     "'base' cannot be used in a static context");
                    return result;
                }
                if (current_class_.base_class == nullptr) {
                    diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                     "'base' can only be used in a derived class");
                    return result;
                }
                result.kind = EntityResolution::Kind::Value;
                result.via_base = true;
                result.value = convert_expression(make_named_type(*current_class_.base_class),
                                                  make_this_expression(expression.line, expression.column));
                return result;
            }

            if (const auto* member = dynamic_cast<const MemberAccessExpressionSyntax*>(&expression)) {
                EntityResolution base = bind_entity(*member->target);
                if (base.kind == EntityResolution::Kind::Error) {
                    return {};
                }
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
                        result.type_symbol = make_named_type(*class_found->second);
                        return result;
                    }
                    const auto enum_found = program_.semantic_model.enums_by_full_name.find(candidate);
                    if (enum_found != program_.semantic_model.enums_by_full_name.end()) {
                        EntityResolution result;
                        result.kind = EntityResolution::Kind::Type;
                        result.type_symbol = make_named_type(*enum_found->second);
                        return result;
                    }
                    diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                     "Unknown member '" + member->member_name + "' on namespace '" + base.namespace_name + "'");
                    return {};
                }

                if (base.kind == EntityResolution::Kind::Type) {
                    if (base.type_symbol != nullptr && base.type_symbol->kind == TypeKind::Enum &&
                        base.type_symbol->enum_symbol != nullptr) {
                        const auto* enum_member =
                            select_enum_member(*base.type_symbol->enum_symbol, member->member_name);
                        if (enum_member != nullptr) {
                            EntityResolution result;
                            result.kind = EntityResolution::Kind::Value;
                            auto value = std::make_unique<BoundLiteralExpression>();
                            value->kind = BoundExpressionKind::Literal;
                            value->type = base.type_symbol;
                            value->line = expression.line;
                            value->column = expression.column;
                            value->value = enum_member->value;
                            result.value = std::move(value);
                            return result;
                        }

                        diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                         "Unknown enum member '" + member->member_name + "' on enum '" +
                                             base.type_symbol->display_name + "'");
                        return {};
                    }

                    if (base.type_symbol == nullptr ||
                        (base.type_symbol->kind != TypeKind::Class && base.type_symbol->kind != TypeKind::Struct) ||
                        base.type_symbol->class_symbol == nullptr) {
                        diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                         "Type '" + (base.type_symbol != nullptr ? base.type_symbol->display_name : string("error")) +
                                             "' does not contain static members");
                        return {};
                    }

                    const ClassSymbol& type_symbol = *base.type_symbol->class_symbol;
                    bool found_inaccessible = false;
                    if (const auto* field = select_field(type_symbol, member->member_name, true, &found_inaccessible)) {
                        EntityResolution result;
                        result.kind = EntityResolution::Kind::Value;
                        result.type_symbol = base.type_symbol;
                        result.value = make_field_expression(nullptr, field, expression.line, expression.column);
                        return result;
                    }
                    EntityResolution result;
                    result.kind = EntityResolution::Kind::MethodGroup;
                    result.type_symbol = base.type_symbol;
                    result.methods = select_methods(type_symbol, member->member_name, true, &found_inaccessible);
                    if (!result.methods.empty()) {
                        return result;
                    }
                    if (found_inaccessible) {
                        if (const auto* field_candidate = find_matching_field(type_symbol, member->member_name, true)) {
                            report_inaccessible(member->member_name,
                                                field_candidate->accessibility,
                                                *field_candidate->owner,
                                                expression.line,
                                                expression.column);
                            return {};
                        }
                        if (const auto* method_candidate = find_matching_method(type_symbol, member->member_name, true)) {
                            report_inaccessible(member->member_name,
                                                method_candidate->accessibility,
                                                *method_candidate->owner,
                                                expression.line,
                                                expression.column);
                            return {};
                        }
                    }
                    {
                        diagnostics_.add(find_file_for_class(&current_class_), expression.line, expression.column,
                                         "Unknown static member '" + member->member_name + "' on type '" +
                                             type_symbol.full_name + "'");
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

                    if (base.value->type == &program_.semantic_model.string_type && member->member_name == "Length") {
                        auto length = std::make_unique<BoundStringLengthExpression>();
                        length->kind = BoundExpressionKind::StringLength;
                        length->type = &program_.semantic_model.int_type;
                        length->line = expression.line;
                        length->column = expression.column;
                        length->string_expression = std::move(base.value);
                        EntityResolution result;
                        result.kind = EntityResolution::Kind::Value;
                        result.value = std::move(length);
                        return result;
                    }

                    if (base.value->type == nullptr ||
                        (base.value->type->kind != TypeKind::Class &&
                         base.value->type->kind != TypeKind::Struct &&
                         base.value->type->kind != TypeKind::Interface) ||
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
                        result.via_base = base.via_base;
                        return result;
                    }
                    if (found_inaccessible) {
                        if (const auto* field_candidate = find_matching_field(*klass, member->member_name, false)) {
                            report_inaccessible(member->member_name,
                                                field_candidate->accessibility,
                                                *field_candidate->owner,
                                                expression.line,
                                                expression.column);
                            return {};
                        }
                        if (const auto* method_candidate = find_matching_method(*klass, member->member_name, false)) {
                            report_inaccessible(member->member_name,
                                                method_candidate->accessibility,
                                                *method_candidate->owner,
                                                expression.line,
                                                expression.column);
                            return {};
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

        const EnumSymbol* resolve_enum(const string& name) const {
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
                const auto found = program_.semantic_model.enums_by_full_name.find(candidate);
                if (found != program_.semantic_model.enums_by_full_name.end()) {
                    return found->second;
                }
            }
            return nullptr;
        }

        const TypeSymbol* resolve_type(const TypeSyntax& type) {
            std::unordered_map<string, const TypeSymbol*> generic_bindings;
            if (current_class_.syntax != nullptr) {
                for (std::size_t index = 0; index < current_class_.syntax->type_parameters.size() &&
                                            index < current_class_.type_parameters.size();
                     ++index) {
                    generic_bindings[current_class_.syntax->type_parameters[index]] = current_class_.type_parameters[index];
                }
            }
            if (current_method_ != nullptr && current_method_->syntax != nullptr) {
                for (std::size_t index = 0; index < current_method_->syntax->type_parameters.size() &&
                                            index < current_method_->type_parameters.size();
                     ++index) {
                    generic_bindings[current_method_->syntax->type_parameters[index]] = current_method_->type_parameters[index];
                }
            }
            return resolve_type_in_context(program_.semantic_model,
                                           diagnostics_,
                                           find_file_for_class(&current_class_),
                                           type,
                                           current_class_.namespace_name,
                                           current_class_.using_namespaces,
                                           generic_bindings.empty() ? nullptr : &generic_bindings);
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
        int loop_depth_ = 0;
        std::unordered_map<string, const ParameterSymbol*> parameter_lookup_;
        vector<std::unique_ptr<VariableSymbol>> locals_;
        vector<std::unordered_map<string, const VariableSymbol*>> scopes_;
    };

    void bind_bodies(BoundProgram& program) {
        for (const auto& class_holder : program.semantic_model.classes) {
            ClassSymbol* klass = class_holder.get();
            if (klass->is_builtin || klass->kind == TypeKind::Interface) {
                continue;
            }

            Binder binder(program, *klass, diagnostics_);
            for (const auto& method : klass->methods) {
                if (method->syntax == nullptr || method->syntax->body == nullptr) {
                    continue;
                }
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
            case '\r':
                out << "\\r";
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
        case TypeKind::Enum:
            return Value{int64_t{0}};
        case TypeKind::Bool:
            return Value{false};
        case TypeKind::String:
        case TypeKind::Class:
        case TypeKind::Struct:
        case TypeKind::Interface:
        case TypeKind::Array:
        case TypeKind::Null:
        case TypeKind::TypeParameter:
            return Value{nullptr};
        case TypeKind::Void:
        case TypeKind::Error:
            return Value{nullptr};
    }
    return Value{nullptr};
}

string enum_member_name(const EnumSymbol* enum_symbol, int64_t value) {
    if (enum_symbol != nullptr) {
        for (const auto& member : enum_symbol->members) {
            if (member->value == value) {
                return member->name;
            }
        }
    }
    return std::to_string(value);
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
                    static_fields_[field.get()] = default_runtime_value(field->type);
                }
            }
        }
    }

    bool run(const vector<string>& args, int* exit_code) {
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

        Value result = invoke_method(*program_.entry_point, nullptr, parameters);
        if (exit_code != nullptr) {
            if (program_.entry_point->return_type == &program_.semantic_model.int_type &&
                std::holds_alternative<int64_t>(result.data)) {
                *exit_code = static_cast<int>(std::get<int64_t>(result.data));
            } else {
                *exit_code = 0;
            }
        }
        return true;
    }

private:
    enum class FlowSignal {
        None,
        Return,
        Break,
        Continue,
    };

    struct Frame {
        std::unordered_map<const ParameterSymbol*, Value> parameters;
        std::unordered_map<const VariableSymbol*, Value> locals;
        std::shared_ptr<RuntimeObject> self;
    };

    struct ExecutionResult {
        FlowSignal signal = FlowSignal::None;
        Value value{};
    };

    string stringify_value(const Value& value, const TypeSymbol* expected_type = nullptr) const {
        if (std::holds_alternative<string>(value.data)) {
            return std::get<string>(value.data);
        }
        if (std::holds_alternative<int64_t>(value.data)) {
            return std::to_string(std::get<int64_t>(value.data));
        }
        if (std::holds_alternative<bool>(value.data)) {
            return std::get<bool>(value.data) ? "true" : "false";
        }
        if (expected_type != nullptr && expected_type->kind == TypeKind::String) {
            return "null";
        }
        return "null";
    }

    void write_console_value(const Value& value, const TypeSymbol* static_type, bool newline) {
        if (static_type != nullptr && static_type->kind == TypeKind::Enum && std::holds_alternative<int64_t>(value.data)) {
            std::cout << enum_member_name(static_type->enum_symbol, std::get<int64_t>(value.data));
        } else if (std::holds_alternative<string>(value.data)) {
            std::cout << std::get<string>(value.data);
        } else if (std::holds_alternative<int64_t>(value.data)) {
            std::cout << std::get<int64_t>(value.data);
        } else if (std::holds_alternative<bool>(value.data)) {
            std::cout << (std::get<bool>(value.data) ? "true" : "false");
        } else {
            std::cout << "null";
        }
        if (newline) {
            std::cout << '\n';
        }
    }

    Value default_runtime_value(const TypeSymbol* type) {
        if (type != nullptr && type->kind == TypeKind::Struct && type->class_symbol != nullptr) {
            auto instance = std::make_shared<RuntimeObject>();
            instance->class_symbol = type->class_symbol;
            initialize_instance_fields(*type->class_symbol, instance);
            return Value{instance};
        }
        return default_value_for_type(type);
    }

    std::shared_ptr<RuntimeObject> clone_object_value(const std::shared_ptr<RuntimeObject>& instance,
                                                      const ClassSymbol& type) {
        if (instance == nullptr) {
            return nullptr;
        }
        auto clone = std::make_shared<RuntimeObject>();
        clone->class_symbol = instance->class_symbol;
        for (const auto& field : type.fields) {
            if (field->is_static) {
                continue;
            }
            const auto found = instance->fields.find(field.get());
            clone->fields[field.get()] =
                found != instance->fields.end() ? copy_value_for_type(found->second, field->type) : default_runtime_value(field->type);
        }
        if (type.base_class != nullptr) {
            auto base_clone = clone_object_value(instance, *type.base_class);
            if (base_clone != nullptr) {
                for (const auto& [field_symbol, field_value] : base_clone->fields) {
                    clone->fields[field_symbol] = field_value;
                }
            }
        }
        return clone;
    }

    Value copy_value_for_type(const Value& value, const TypeSymbol* type, bool box_struct_to_interface = false) {
        if (type == nullptr) {
            return value;
        }
        if (type->kind == TypeKind::Struct) {
            if (!std::holds_alternative<std::shared_ptr<RuntimeObject>>(value.data)) {
                return default_runtime_value(type);
            }
            return Value{clone_object_value(std::get<std::shared_ptr<RuntimeObject>>(value.data), *type->class_symbol)};
        }
        if (type->kind == TypeKind::Interface && box_struct_to_interface &&
            std::holds_alternative<std::shared_ptr<RuntimeObject>>(value.data)) {
            return Value{clone_object_value(std::get<std::shared_ptr<RuntimeObject>>(value.data),
                                            *std::get<std::shared_ptr<RuntimeObject>>(value.data)->class_symbol)};
        }
        return value;
    }

    const MethodSymbol* resolve_virtual_method_target(const MethodSymbol& root,
                                                      const std::shared_ptr<RuntimeObject>& receiver) const {
        if (receiver == nullptr || receiver->class_symbol == nullptr || root.virtual_root == nullptr) {
            return &root;
        }
        const MethodSymbol* root_method = root.virtual_root;
        for (auto current = receiver->class_symbol; current != nullptr; current = current->base_class) {
            for (const auto& method : current->methods) {
                if (method.get() == root_method || method->virtual_root == root_method) {
                    return method.get();
                }
            }
        }
        return &root;
    }

    const MethodSymbol* resolve_interface_method_target(const MethodSymbol& interface_method,
                                                        const std::shared_ptr<RuntimeObject>& receiver) const {
        if (receiver == nullptr || receiver->class_symbol == nullptr) {
            return &interface_method;
        }
        const string target_signature =
            member_signature_key(interface_method.name, false, interface_method.parameters);
        for (auto current = receiver->class_symbol; current != nullptr; current = current->base_class) {
            for (const auto& method : current->methods) {
                if (method->is_static) {
                    continue;
                }
                if (member_signature_key(method->name, method->is_static, method->parameters) == target_signature) {
                    return method.get();
                }
            }
        }
        return &interface_method;
    }

    const ConstructorSymbol* find_parameterless_declared_constructor(const ClassSymbol& klass) const {
        for (const auto& constructor : klass.constructors) {
            if (constructor->parameters.empty()) {
                return constructor.get();
            }
        }
        return nullptr;
    }

    void initialize_instance_fields(const ClassSymbol& klass, const std::shared_ptr<RuntimeObject>& instance) {
        if (klass.base_class != nullptr) {
            initialize_instance_fields(*klass.base_class, instance);
        }
        for (const auto& field : klass.fields) {
            if (field->is_static) {
                continue;
            }
            instance->fields[field.get()] = default_runtime_value(field->type);
        }
    }

    void invoke_implicit_constructor(const ClassSymbol& klass, const std::shared_ptr<RuntimeObject>& receiver) {
        if (klass.base_class == nullptr) {
            return;
        }

        if (const auto* constructor = find_parameterless_declared_constructor(*klass.base_class)) {
            invoke_constructor(*constructor, receiver, {});
            return;
        }

        invoke_implicit_constructor(*klass.base_class, receiver);
    }

    Value invoke_method(const MethodSymbol& method,
                        std::shared_ptr<RuntimeObject> receiver,
                        const vector<Value>& arguments,
                        const vector<const TypeSymbol*>* argument_types = nullptr) {
        if (method.is_builtin) {
            if (method.owner == program_.semantic_model.console_class &&
                (method.name == "Write" || method.name == "WriteLine")) {
                const TypeSymbol* argument_type =
                    (argument_types != nullptr && !argument_types->empty()) ? (*argument_types)[0] : nullptr;
                write_console_value(arguments.empty() ? Value{nullptr} : arguments[0], argument_type, method.name == "WriteLine");
                return Value{nullptr};
            }
            if (method.owner == program_.semantic_model.file_class && method.name == "Exists") {
                if (arguments.empty() || !std::holds_alternative<string>(arguments[0].data)) {
                    return Value{false};
                }
                return Value{fs::exists(std::get<string>(arguments[0].data))};
            }
            if (method.owner == program_.semantic_model.file_class && method.name == "ReadAllText") {
                if (arguments.empty() || !std::holds_alternative<string>(arguments[0].data)) {
                    return Value{nullptr};
                }
                std::ifstream input(std::get<string>(arguments[0].data));
                if (!input) {
                    return Value{nullptr};
                }
                std::ostringstream buffer;
                buffer << input.rdbuf();
                return Value{buffer.str()};
            }
            if (method.owner == program_.semantic_model.file_class && method.name == "WriteAllText") {
                if (arguments.size() < 2 || !std::holds_alternative<string>(arguments[0].data)) {
                    throw std::runtime_error("System.IO.File.WriteAllText requires a valid path");
                }
                const string& path = std::get<string>(arguments[0].data);
                std::ofstream output(path);
                if (!output) {
                    throw std::runtime_error("Could not write file '" + path + "'");
                }
                if (std::holds_alternative<string>(arguments[1].data)) {
                    output << std::get<string>(arguments[1].data);
                }
                return Value{nullptr};
            }
        }

        const MethodSymbol* body_key = &method;
        const auto initial = program_.methods.find(body_key);
        if (initial == program_.methods.end() && method.generic_definition != nullptr) {
            body_key = method.generic_definition;
        }
        const auto found = program_.methods.find(body_key);
        if (found == program_.methods.end()) {
            return default_value_for_type(method.return_type);
        }

        Frame frame;
        frame.self = std::move(receiver);
        for (std::size_t index = 0; index < body_key->parameters.size() && index < arguments.size(); ++index) {
            const TypeSymbol* parameter_type =
                index < method.parameters.size() ? method.parameters[index].type : body_key->parameters[index].type;
            frame.parameters[&body_key->parameters[index]] = copy_value_for_type(arguments[index], parameter_type);
        }

        const ExecutionResult result = execute_statement(*found->second->body, frame);
        if (result.signal == FlowSignal::Return) {
            return result.value;
        }
        return default_value_for_type(method.return_type);
    }

    void invoke_constructor(const ConstructorSymbol& constructor,
                            const std::shared_ptr<RuntimeObject>& receiver,
                            const vector<Value>& arguments) {
        const ConstructorSymbol* body_key = &constructor;
        const auto initial = program_.constructors.find(body_key);
        if (initial == program_.constructors.end() && constructor.syntax != nullptr) {
            for (const auto& candidate : constructor.owner->constructors) {
                if (candidate.get()->syntax == constructor.syntax) {
                    body_key = candidate.get();
                    break;
                }
            }
        }
        const auto found = program_.constructors.find(body_key);

        Frame frame;
        frame.self = receiver;
        for (std::size_t index = 0; index < body_key->parameters.size() && index < arguments.size(); ++index) {
            const TypeSymbol* parameter_type =
                index < constructor.parameters.size() ? constructor.parameters[index].type : body_key->parameters[index].type;
            frame.parameters[&body_key->parameters[index]] = copy_value_for_type(arguments[index], parameter_type);
        }
        if (found != program_.constructors.end() && found->second->base_constructor != nullptr) {
            vector<Value> base_arguments;
            for (const auto& argument : found->second->base_arguments) {
                base_arguments.push_back(evaluate_expression(*argument, frame));
            }
            invoke_constructor(*found->second->base_constructor, receiver, base_arguments);
        } else if (constructor.owner != nullptr) {
            invoke_implicit_constructor(*constructor.owner, receiver);
        }

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
                    if (result.signal != FlowSignal::None) {
                        return result;
                    }
                }
                return {};
            }
            case BoundStatementKind::VariableDeclaration: {
                const auto& declaration = static_cast<const BoundVariableDeclarationStatement&>(statement);
                Value value = declaration.initializer != nullptr
                                  ? evaluate_expression(*declaration.initializer, frame)
                                  : default_runtime_value(declaration.variable->type);
                frame.locals[declaration.variable] = copy_value_for_type(value, declaration.variable->type);
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
                    if (result.signal == FlowSignal::Return) {
                        return result;
                    }
                    if (result.signal == FlowSignal::Break) {
                        return {};
                    }
                    if (result.signal == FlowSignal::Continue) {
                        continue;
                    }
                }
                return {};
            }
            case BoundStatementKind::For: {
                const auto& for_statement = static_cast<const BoundForStatement&>(statement);
                if (for_statement.initializer != nullptr) {
                    ExecutionResult init_result = execute_statement(*for_statement.initializer, frame);
                    if (init_result.signal != FlowSignal::None) {
                        return init_result;
                    }
                }
                while (for_statement.condition == nullptr ||
                       std::get<bool>(evaluate_expression(*for_statement.condition, frame).data)) {
                    ExecutionResult result = execute_statement(*for_statement.body, frame);
                    if (result.signal == FlowSignal::Return) {
                        return result;
                    }
                    if (result.signal == FlowSignal::Break) {
                        return {};
                    }
                    if (for_statement.update != nullptr) {
                        evaluate_expression(*for_statement.update, frame);
                    }
                    if (result.signal == FlowSignal::Continue) {
                        continue;
                    }
                }
                return {};
            }
            case BoundStatementKind::Break:
                return ExecutionResult{FlowSignal::Break, Value{nullptr}};
            case BoundStatementKind::Continue:
                return ExecutionResult{FlowSignal::Continue, Value{nullptr}};
            case BoundStatementKind::Return: {
                const auto& return_statement = static_cast<const BoundReturnStatement&>(statement);
                if (return_statement.expression != nullptr) {
                    Value value = evaluate_expression(*return_statement.expression, frame);
                    return ExecutionResult{FlowSignal::Return,
                                           copy_value_for_type(value,
                                                               return_statement.expression != nullptr
                                                                   ? return_statement.expression->type
                                                                   : nullptr)};
                }
                return ExecutionResult{FlowSignal::Return, Value{nullptr}};
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
            case BoundExpressionKind::ArrayIndex: {
                const auto& access = static_cast<const BoundArrayIndexExpression&>(expression);
                Value array_value = evaluate_expression(*access.array_expression, frame);
                Value index_value = evaluate_expression(*access.index_expression, frame);
                if (!std::holds_alternative<std::shared_ptr<RuntimeArray>>(array_value.data)) {
                    return Value{nullptr};
                }
                const auto& array = std::get<std::shared_ptr<RuntimeArray>>(array_value.data);
                const int64_t index = std::get<int64_t>(index_value.data);
                if (array == nullptr || index < 0 || static_cast<std::size_t>(index) >= array->elements.size()) {
                    throw std::runtime_error("Array index out of range");
                }
                return array->elements[static_cast<std::size_t>(index)];
            }
            case BoundExpressionKind::StringIndex: {
                const auto& access = static_cast<const BoundStringIndexExpression&>(expression);
                Value string_value = evaluate_expression(*access.string_expression, frame);
                Value index_value = evaluate_expression(*access.index_expression, frame);
                if (!std::holds_alternative<string>(string_value.data)) {
                    return Value{nullptr};
                }
                const string& source = std::get<string>(string_value.data);
                const int64_t index = std::get<int64_t>(index_value.data);
                if (index < 0 || static_cast<std::size_t>(index) >= source.size()) {
                    throw std::runtime_error("String index out of range");
                }
                return Value{string(1, source[static_cast<std::size_t>(index)])};
            }
            case BoundExpressionKind::StringLength: {
                const auto& length = static_cast<const BoundStringLengthExpression&>(expression);
                Value string_value = evaluate_expression(*length.string_expression, frame);
                if (std::holds_alternative<string>(string_value.data)) {
                    return Value{static_cast<int64_t>(std::get<string>(string_value.data).size())};
                }
                return Value{int64_t{0}};
            }
            case BoundExpressionKind::Assignment: {
                const auto& assignment = static_cast<const BoundAssignmentExpression&>(expression);
                Value value = evaluate_expression(*assignment.expression, frame);
                Value stored = copy_value_for_type(value, assignment.target->type);
                access_assignable(*assignment.target, frame) = stored;
                return stored;
            }
            case BoundExpressionKind::Conversion: {
                const auto& conversion = static_cast<const BoundConversionExpression&>(expression);
                Value converted = evaluate_expression(*conversion.expression, frame);
                const bool box_struct_to_interface =
                    conversion.type != nullptr &&
                    conversion.type->kind == TypeKind::Interface &&
                    conversion.expression != nullptr &&
                    conversion.expression->type != nullptr &&
                    conversion.expression->type->kind == TypeKind::Struct;
                return copy_value_for_type(converted, conversion.type, box_struct_to_interface);
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
                        if (binary.type == &program_.semantic_model.string_type) {
                            return Value{stringify_value(left, binary.left->type) + stringify_value(right, binary.right->type)};
                        }
                        return Value{std::get<int64_t>(left.data) + std::get<int64_t>(right.data)};
                    case TokenKind::Minus:
                        return Value{std::get<int64_t>(left.data) - std::get<int64_t>(right.data)};
                    case TokenKind::Star:
                        return Value{std::get<int64_t>(left.data) * std::get<int64_t>(right.data)};
                    case TokenKind::Slash:
                        return Value{std::get<int64_t>(left.data) / std::get<int64_t>(right.data)};
                    case TokenKind::Percent:
                        return Value{std::get<int64_t>(left.data) % std::get<int64_t>(right.data)};
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
                vector<const TypeSymbol*> argument_types;
                for (const auto& argument : call.arguments) {
                    argument_types.push_back(argument->type);
                }
                const MethodSymbol* target = call.method;
                if (call.dispatch_interface) {
                    target = resolve_interface_method_target(*call.method, receiver);
                } else if (call.dispatch_virtual) {
                    target = resolve_virtual_method_target(*call.method, receiver);
                }
                return invoke_method(*target, receiver, arguments, &argument_types);
            }
            case BoundExpressionKind::NewObject: {
                const auto& creation = static_cast<const BoundNewExpression&>(expression);
                auto instance = std::make_shared<RuntimeObject>();
                instance->class_symbol = creation.class_symbol;
                initialize_instance_fields(*creation.class_symbol, instance);
                vector<Value> arguments;
                for (const auto& argument : creation.arguments) {
                    arguments.push_back(evaluate_expression(*argument, frame));
                }
                if (creation.constructor != nullptr) {
                    invoke_constructor(*creation.constructor, instance, arguments);
                } else if (!creation.zero_initialize) {
                    invoke_implicit_constructor(*creation.class_symbol, instance);
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
        case TypeKind::Enum:
            return "int64_t";
        case TypeKind::Bool:
            return "bool";
        case TypeKind::String:
            return "const char*";
        case TypeKind::Array:
            return "HyStringArray";
        case TypeKind::Class:
        case TypeKind::Struct:
            return sanitize_c_name(type->class_symbol->full_name) + "*";
        case TypeKind::Interface:
        case TypeKind::TypeParameter:
            return "void*";
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
        emit_enum_helpers(out);
        emit_classes(out);
        emit_upcast_helpers(out);
        emit_method_prototypes(out);
        emit_dispatch_helpers(out);
        emit_constructors(out);
        emit_methods(out);
        emit_main(out);
        return out.str();
    }

    string emit_library() {
        std::ostringstream out;
        emit_prelude(out);
        emit_enum_helpers(out);
        emit_classes(out);
        emit_upcast_helpers(out);
        emit_method_prototypes(out);
        emit_dispatch_helpers(out);
        emit_constructors(out);
        emit_methods(out);
        return out.str();
    }

private:
    void collect_class_emission_order(const ClassSymbol& klass,
                                      std::unordered_set<const ClassSymbol*>& visited,
                                      vector<const ClassSymbol*>& order) const {
        if (klass.is_builtin || klass.kind == TypeKind::Interface || !visited.insert(&klass).second) {
            return;
        }
        if (klass.base_class != nullptr) {
            collect_class_emission_order(*klass.base_class, visited, order);
        }
        order.push_back(&klass);
    }

    vector<const ClassSymbol*> class_emission_order() const {
        vector<const ClassSymbol*> order;
        std::unordered_set<const ClassSymbol*> visited;
        for (const auto& class_holder : program_.semantic_model.classes) {
            collect_class_emission_order(*class_holder, visited, order);
        }
        return order;
    }

    string class_struct_name(const ClassSymbol& klass) const {
        return sanitize_c_name(klass.full_name);
    }

    string static_field_name(const FieldSymbol& field) const {
        return sanitize_c_name(field.owner->full_name + "_static_" + field.name);
    }

    string method_name(const MethodSymbol& method) const {
        return sanitize_c_name(method.owner->full_name + "_method_" + std::to_string(method.slot) + "_" + method.name);
    }

    string constructor_name(const ConstructorSymbol& ctor) const {
        return sanitize_c_name(ctor.owner->full_name + "_ctor_" + std::to_string(ctor.slot));
    }

    string implicit_constructor_name(const ClassSymbol& klass) const {
        return sanitize_c_name("hy_ctor_implicit_" + klass.full_name);
    }

    string new_helper_name(const ClassSymbol& klass, int constructor_slot) const {
        return sanitize_c_name("hy_new_" + klass.full_name + "_" + std::to_string(constructor_slot));
    }

    string zero_helper_name(const ClassSymbol& klass) const {
        return sanitize_c_name("hy_zero_" + klass.full_name);
    }

    string base_field_name() const {
        return "__base";
    }

    string header_field_name() const {
        return "__header";
    }

    string header_access_expression(const string& expression, const ClassSymbol& klass) const {
        if (klass.base_class == nullptr) {
            return expression + "->" + header_field_name() + ".type_id";
        }
        string result = expression + "->" + base_field_name();
        for (const ClassSymbol* current = klass.base_class; current != nullptr && current->base_class != nullptr;
             current = current->base_class) {
            result += "." + base_field_name();
        }
        return result + "." + header_field_name() + ".type_id";
    }

    string upcast_name(const ClassSymbol& derived, const ClassSymbol& base) const {
        return sanitize_c_name("hy_upcast_" + derived.full_name + "_to_" + base.full_name);
    }

    string enum_to_string_name(const EnumSymbol& enum_symbol) const {
        return sanitize_c_name("hy_enum_to_string_" + enum_symbol.full_name);
    }

    string virtual_dispatch_name(const MethodSymbol& root_method) const {
        return sanitize_c_name("hy_virtual_dispatch_" + root_method.owner->full_name + "_" +
                               std::to_string(root_method.slot) + "_" + root_method.name);
    }

    string interface_dispatch_name(const MethodSymbol& interface_method) const {
        return sanitize_c_name("hy_interface_dispatch_" + interface_method.owner->full_name + "_" +
                               std::to_string(interface_method.slot) + "_" + interface_method.name);
    }

    int emitted_type_id(const ClassSymbol& klass) const {
        const auto order = class_emission_order();
        for (std::size_t index = 0; index < order.size(); ++index) {
            if (order[index] == &klass) {
                return static_cast<int>(index + 1);
            }
        }
        return -1;
    }

    const ConstructorSymbol* find_parameterless_declared_constructor(const ClassSymbol& klass) const {
        for (const auto& ctor : klass.constructors) {
            if (ctor->parameters.empty()) {
                return ctor.get();
            }
        }
        return nullptr;
    }

    void emit_prelude(std::ostringstream& out) {
        out << "#include <stdbool.h>\n";
        out << "#include <stdint.h>\n";
        out << "#include <stdio.h>\n";
        out << "#include <stdlib.h>\n";
        out << "#include <string.h>\n\n";
        out << "typedef struct {\n";
        out << "    int32_t type_id;\n";
        out << "} HyObjectHeader;\n\n";
        out << "typedef struct {\n";
        out << "    int64_t length;\n";
        out << "    const char** items;\n";
        out << "} HyStringArray;\n\n";
        out << "static int32_t hy_object_type_id(const void* value) {\n";
        out << "    return value == NULL ? -1 : ((const HyObjectHeader*)value)->type_id;\n";
        out << "}\n\n";
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
        out << "static void hy_runtime_fail(const char* message) {\n";
        out << "    fprintf(stderr, \"%s\\n\", message);\n";
        out << "    exit(1);\n";
        out << "}\n\n";
        out << "static const char* hy_array_index(HyStringArray array, int64_t index) {\n";
        out << "    if (array.items == NULL || index < 0 || index >= array.length) {\n";
        out << "        hy_runtime_fail(\"Array index out of range\");\n";
        out << "    }\n";
        out << "    return array.items[index];\n";
        out << "}\n";
        out << "static const char* hy_alloc_string_copy(const char* value) {\n";
        out << "    const char* safe_value = value == NULL ? \"null\" : value;\n";
        out << "    size_t length = strlen(safe_value);\n";
        out << "    char* result = (char*)hy_alloc_managed(length + 1);\n";
        out << "    memcpy(result, safe_value, length + 1);\n";
        out << "    return result;\n";
        out << "}\n";
        out << "static const char* hy_string_index(const char* value, int64_t index) {\n";
        out << "    const char* safe_value = value == NULL ? \"\" : value;\n";
        out << "    size_t length = strlen(safe_value);\n";
        out << "    if (index < 0 || (size_t)index >= length) {\n";
        out << "        hy_runtime_fail(\"String index out of range\");\n";
        out << "    }\n";
        out << "    char* result = (char*)hy_alloc_managed(2);\n";
        out << "    result[0] = safe_value[index];\n";
        out << "    result[1] = '\\0';\n";
        out << "    return result;\n";
        out << "}\n";
        out << "static int64_t hy_string_length(const char* value) {\n";
        out << "    return (int64_t)strlen(value == NULL ? \"\" : value);\n";
        out << "}\n";
        out << "static const char* hy_string_from_int(int64_t value) {\n";
        out << "    char buffer[32];\n";
        out << "    snprintf(buffer, sizeof(buffer), \"%lld\", (long long)value);\n";
        out << "    return hy_alloc_string_copy(buffer);\n";
        out << "}\n";
        out << "static const char* hy_string_from_bool(bool value) {\n";
        out << "    return hy_alloc_string_copy(value ? \"true\" : \"false\");\n";
        out << "}\n";
        out << "static const char* hy_string_concat(const char* left, const char* right) {\n";
        out << "    const char* safe_left = left == NULL ? \"null\" : left;\n";
        out << "    const char* safe_right = right == NULL ? \"null\" : right;\n";
        out << "    size_t left_length = strlen(safe_left);\n";
        out << "    size_t right_length = strlen(safe_right);\n";
        out << "    char* result = (char*)hy_alloc_managed(left_length + right_length + 1);\n";
        out << "    memcpy(result, safe_left, left_length);\n";
        out << "    memcpy(result + left_length, safe_right, right_length + 1);\n";
        out << "    return result;\n";
        out << "}\n";
        out << "static bool hy_string_equals(const char* left, const char* right) {\n";
        out << "    if (left == NULL || right == NULL) {\n";
        out << "        return left == right;\n";
        out << "    }\n";
        out << "    return strcmp(left, right) == 0;\n";
        out << "}\n";
        out << "static void hy_console_write_string(const char* value) {\n";
        out << "    printf(\"%s\", value == NULL ? \"null\" : value);\n";
        out << "}\n";
        out << "static void hy_console_write_int(int64_t value) {\n";
        out << "    printf(\"%lld\", (long long)value);\n";
        out << "}\n";
        out << "static void hy_console_write_bool(bool value) {\n";
        out << "    printf(\"%s\", value ? \"true\" : \"false\");\n";
        out << "}\n";
        out << "static void hy_console_writeline_string(const char* value) {\n";
        out << "    printf(\"%s\\n\", value == NULL ? \"null\" : value);\n";
        out << "}\n";
        out << "static void hy_console_writeline_int(int64_t value) {\n";
        out << "    printf(\"%lld\\n\", (long long)value);\n";
        out << "}\n";
        out << "static void hy_console_writeline_bool(bool value) {\n";
        out << "    printf(\"%s\\n\", value ? \"true\" : \"false\");\n";
        out << "}\n\n";
        out << "static bool hy_file_exists(const char* path) {\n";
        out << "    if (path == NULL) {\n";
        out << "        return false;\n";
        out << "    }\n";
        out << "    FILE* file = fopen(path, \"rb\");\n";
        out << "    if (file == NULL) {\n";
        out << "        return false;\n";
        out << "    }\n";
        out << "    fclose(file);\n";
        out << "    return true;\n";
        out << "}\n";
        out << "static const char* hy_file_read_all_text(const char* path) {\n";
        out << "    if (path == NULL) {\n";
        out << "        return NULL;\n";
        out << "    }\n";
        out << "    FILE* file = fopen(path, \"rb\");\n";
        out << "    if (file == NULL) {\n";
        out << "        return NULL;\n";
        out << "    }\n";
        out << "    if (fseek(file, 0, SEEK_END) != 0) {\n";
        out << "        fclose(file);\n";
        out << "        return NULL;\n";
        out << "    }\n";
        out << "    long size = ftell(file);\n";
        out << "    if (size < 0) {\n";
        out << "        fclose(file);\n";
        out << "        return NULL;\n";
        out << "    }\n";
        out << "    rewind(file);\n";
        out << "    char* buffer = (char*)hy_alloc_managed((size_t)size + 1);\n";
        out << "    size_t read_count = fread(buffer, 1, (size_t)size, file);\n";
        out << "    fclose(file);\n";
        out << "    buffer[read_count] = '\\0';\n";
        out << "    return buffer;\n";
        out << "}\n";
        out << "static void hy_file_write_all_text(const char* path, const char* content) {\n";
        out << "    if (path == NULL) {\n";
        out << "        hy_runtime_fail(\"Hylang file write failed\");\n";
        out << "    }\n";
        out << "    FILE* file = fopen(path, \"wb\");\n";
        out << "    if (file == NULL) {\n";
        out << "        hy_runtime_fail(\"Hylang file write failed\");\n";
        out << "    }\n";
        out << "    const char* safe_content = content == NULL ? \"\" : content;\n";
        out << "    size_t length = strlen(safe_content);\n";
        out << "    if (length > 0 && fwrite(safe_content, 1, length, file) != length) {\n";
        out << "        fclose(file);\n";
        out << "        hy_runtime_fail(\"Hylang file write failed\");\n";
        out << "    }\n";
        out << "    if (fclose(file) != 0) {\n";
        out << "        hy_runtime_fail(\"Hylang file write failed\");\n";
        out << "    }\n";
        out << "}\n\n";
    }

    void emit_enum_helpers(std::ostringstream& out) {
        for (const auto& enum_holder : program_.semantic_model.enums) {
            out << "static const char* " << enum_to_string_name(*enum_holder) << "(int64_t value) {\n";
            out << "    switch (value) {\n";
            for (const auto& member : enum_holder->members) {
                out << "        case " << member->value << ": return \"" << escape_c_string(member->name) << "\";\n";
            }
            out << "        default: return hy_string_from_int(value);\n";
            out << "    }\n";
            out << "}\n\n";
        }
    }

    void emit_classes(std::ostringstream& out) {
        const auto classes = class_emission_order();
        for (const auto* klass : classes) {
            out << "typedef struct " << class_struct_name(*klass) << " " << class_struct_name(*klass) << ";\n";
        }
        out << "\n";
        for (const auto* klass : classes) {
            out << "struct " << class_struct_name(*klass) << " {\n";
            if (klass->base_class != nullptr) {
                out << "    " << class_struct_name(*klass->base_class) << " " << base_field_name() << ";\n";
            } else {
                out << "    HyObjectHeader " << header_field_name() << ";\n";
            }
            for (const auto& field : klass->fields) {
                if (field->is_static) {
                    continue;
                }
                out << "    " << c_type_name(field->type) << " " << sanitize_c_name(field->name) << ";\n";
            }
            out << "};\n\n";
        }
        for (const auto* klass : classes) {
            for (const auto& field : klass->fields) {
                if (!field->is_static) {
                    continue;
                }
                out << c_type_name(field->type) << " " << static_field_name(*field) << " = "
                    << default_expression(field->type) << ";\n";
            }
        }
        out << "\n";
    }

    void emit_upcast_helpers(std::ostringstream& out) {
        for (const auto* klass : class_emission_order()) {
            if (klass->base_class == nullptr) {
                continue;
            }
            out << "static " << class_struct_name(*klass->base_class) << "* "
                << upcast_name(*klass, *klass->base_class) << "("
                << class_struct_name(*klass) << "* value) {\n";
            out << "    return value == NULL ? NULL : &value->" << base_field_name() << ";\n";
            out << "}\n\n";
        }
    }

    const MethodSymbol* virtual_dispatch_target_for_type(const ClassSymbol& runtime_type,
                                                         const MethodSymbol& root_method) const {
        for (auto current = &runtime_type; current != nullptr; current = current->base_class) {
            for (const auto& method : current->methods) {
                if (method.get() == &root_method || method->virtual_root == &root_method) {
                    return method.get();
                }
            }
        }
        return &root_method;
    }

    void collect_interface_methods(const ClassSymbol& interface_symbol,
                                   std::vector<const MethodSymbol*>& methods,
                                   std::unordered_set<string>& seen) const {
        for (const auto* base_interface : interface_symbol.interfaces) {
            collect_interface_methods(*base_interface, methods, seen);
        }
        for (const auto& method : interface_symbol.methods) {
            const string signature = member_signature_key(method->name, method->is_static, method->parameters);
            if (seen.insert(signature).second) {
                methods.push_back(method.get());
            }
        }
    }

    const MethodSymbol* interface_dispatch_target_for_type(const ClassSymbol& runtime_type,
                                                           const MethodSymbol& interface_method) const {
        const string signature = member_signature_key(interface_method.name, false, interface_method.parameters);
        for (auto current = &runtime_type; current != nullptr; current = current->base_class) {
            for (const auto& method : current->methods) {
                if (!method->is_static &&
                    member_signature_key(method->name, method->is_static, method->parameters) == signature) {
                    return method.get();
                }
            }
        }
        return nullptr;
    }

    void emit_dispatch_helpers(std::ostringstream& out) {
        for (const auto* klass : class_emission_order()) {
            for (const auto& method : klass->methods) {
                if (method->virtual_root != method.get()) {
                    continue;
                }

                out << c_type_name(method->return_type) << " " << virtual_dispatch_name(*method) << "("
                    << class_struct_name(*method->owner) << "* self";
                for (const auto& parameter : method->parameters) {
                    out << ", " << c_type_name(parameter.type) << " " << sanitize_c_name(parameter.name);
                }
                out << ") {\n";
                out << "    switch (hy_object_type_id(self)) {\n";
                for (const auto* runtime_type : class_emission_order()) {
                    if (!is_same_or_derived_from(runtime_type, method->owner)) {
                        continue;
                    }
                    const MethodSymbol* target = virtual_dispatch_target_for_type(*runtime_type, *method);
                    out << "        case " << emitted_type_id(*runtime_type) << ": return " << method_name(*target) << "(("
                        << class_struct_name(*runtime_type) << "*)self";
                    for (const auto& parameter : method->parameters) {
                        out << ", " << sanitize_c_name(parameter.name);
                    }
                    out << ");\n";
                }
                out << "        default:\n";
                out << "            hy_runtime_fail(\"Virtual dispatch failed\");\n";
                if (method->return_type != &program_.semantic_model.void_type) {
                    out << "            return " << default_expression(method->return_type) << ";\n";
                } else {
                    out << "            return;\n";
                }
                out << "    }\n";
                out << "}\n\n";
            }
        }

        std::unordered_set<string> emitted_interface_helpers;
        for (const auto& interface_holder : program_.semantic_model.classes) {
            if (interface_holder->kind != TypeKind::Interface) {
                continue;
            }

            std::vector<const MethodSymbol*> interface_methods;
            std::unordered_set<string> seen;
            collect_interface_methods(*interface_holder, interface_methods, seen);
            for (const auto* interface_method : interface_methods) {
                if (!emitted_interface_helpers.insert(interface_dispatch_name(*interface_method)).second) {
                    continue;
                }
                out << c_type_name(interface_method->return_type) << " " << interface_dispatch_name(*interface_method)
                    << "(void* self";
                for (const auto& parameter : interface_method->parameters) {
                    out << ", " << c_type_name(parameter.type) << " " << sanitize_c_name(parameter.name);
                }
                out << ") {\n";
                out << "    switch (hy_object_type_id(self)) {\n";
                for (const auto* runtime_type : class_emission_order()) {
                    if (!does_type_implement_interface_symbol(runtime_type, interface_holder.get())) {
                        continue;
                    }
                    const MethodSymbol* target = interface_dispatch_target_for_type(*runtime_type, *interface_method);
                    if (target == nullptr) {
                        continue;
                    }
                    out << "        case " << emitted_type_id(*runtime_type) << ": return " << method_name(*target)
                        << "((" << class_struct_name(*runtime_type) << "*)self";
                    for (const auto& parameter : interface_method->parameters) {
                        out << ", " << sanitize_c_name(parameter.name);
                    }
                    out << ");\n";
                }
                out << "        default:\n";
                out << "            hy_runtime_fail(\"Interface dispatch failed\");\n";
                if (interface_method->return_type != &program_.semantic_model.void_type) {
                    out << "            return " << default_expression(interface_method->return_type) << ";\n";
                } else {
                    out << "            return;\n";
                }
                out << "    }\n";
                out << "}\n\n";
            }
        }
    }

    void emit_method_prototypes(std::ostringstream& out) {
        for (const auto* klass : class_emission_order()) {
            out << "void " << implicit_constructor_name(*klass) << "(" << class_struct_name(*klass)
                << "* self);\n";
            if (klass->kind == TypeKind::Struct) {
                out << class_struct_name(*klass) << "* " << zero_helper_name(*klass) << "(void);\n";
            }
            for (const auto& ctor : klass->constructors) {
                out << "void " << constructor_name(*ctor) << "(" << class_struct_name(*klass) << "* self";
                for (const auto& parameter : ctor->parameters) {
                    out << ", " << c_type_name(parameter.type) << " " << sanitize_c_name(parameter.name);
                }
                out << ");\n";
                out << class_struct_name(*klass) << "* " << new_helper_name(*klass, ctor->slot)
                    << "(";
                for (std::size_t index = 0; index < ctor->parameters.size(); ++index) {
                    if (index > 0) {
                        out << ", ";
                    }
                    out << c_type_name(ctor->parameters[index].type) << " " << sanitize_c_name(ctor->parameters[index].name);
                }
                out << ");\n";
            }
            if (klass->constructors.empty()) {
                out << class_struct_name(*klass) << "* " << new_helper_name(*klass, 0) << "(void);\n";
            }
            for (const auto& method : klass->methods) {
                out << c_type_name(method->return_type) << " " << method_name(*method) << "(";
                bool wrote = false;
                if (!method->is_static) {
                    out << class_struct_name(*klass) << "* self";
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
        for (const auto* klass : class_emission_order()) {
            out << "void " << implicit_constructor_name(*klass) << "(" << class_struct_name(*klass)
                << "* self) {\n";
            if (klass->base_class != nullptr) {
                if (const auto* base_ctor = find_parameterless_declared_constructor(*klass->base_class)) {
                    out << "    " << constructor_name(*base_ctor) << "("
                        << emit_class_upcast("self", *klass, *klass->base_class) << ");\n";
                } else {
                    out << "    " << implicit_constructor_name(*klass->base_class) << "("
                        << emit_class_upcast("self", *klass, *klass->base_class) << ");\n";
                }
            }
            out << "    return;\n";
            out << "}\n\n";

            if (klass->kind == TypeKind::Struct) {
                out << class_struct_name(*klass) << "* " << zero_helper_name(*klass) << "(void) {\n";
                out << "    " << class_struct_name(*klass) << "* self = (" << class_struct_name(*klass)
                    << "*)hy_alloc_managed(sizeof(" << class_struct_name(*klass) << "));\n";
                out << "    " << header_access_expression("self", *klass) << " = " << emitted_type_id(*klass) << ";\n";
                out << "    return self;\n";
                out << "}\n\n";
            }

            if (klass->constructors.empty()) {
                out << class_struct_name(*klass) << "* " << new_helper_name(*klass, 0) << "(void) {\n";
                out << "    " << class_struct_name(*klass) << "* self = (" << class_struct_name(*klass)
                    << "*)hy_alloc_managed(sizeof(" << class_struct_name(*klass) << "));\n";
                out << "    " << header_access_expression("self", *klass) << " = " << emitted_type_id(*klass) << ";\n";
                if (klass->kind == TypeKind::Struct) {
                    out << "    return self;\n";
                    out << "}\n\n";
                    continue;
                }
                out << "    " << implicit_constructor_name(*klass) << "(self);\n";
                out << "    return self;\n";
                out << "}\n\n";
                continue;
            }

            for (const auto& ctor : klass->constructors) {
                const auto& bound_body = *program_.constructors.at(ctor.get());
                out << "void " << constructor_name(*ctor) << "(" << class_struct_name(*klass) << "* self";
                for (const auto& parameter : ctor->parameters) {
                    out << ", " << c_type_name(parameter.type) << " " << sanitize_c_name(parameter.name);
                }
                out << ") {\n";
                if (bound_body.base_constructor != nullptr) {
                    out << "    " << constructor_name(*bound_body.base_constructor) << "("
                        << emit_class_upcast("self", *klass, *bound_body.base_constructor->owner);
                    for (const auto& argument : bound_body.base_arguments) {
                        out << ", " << emit_expression(*argument);
                    }
                    out << ");\n";
                } else if (klass->kind == TypeKind::Class) {
                    out << "    " << implicit_constructor_name(*klass) << "(self);\n";
                }
                emit_block(out, *bound_body.body, 1);
                out << "}\n\n";

                out << class_struct_name(*klass) << "* " << new_helper_name(*klass, ctor->slot)
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
                out << "    " << class_struct_name(*klass) << "* self = (" << class_struct_name(*klass)
                    << "*)hy_alloc_managed(sizeof(" << class_struct_name(*klass) << "));\n";
                out << "    " << header_access_expression("self", *klass) << " = " << emitted_type_id(*klass) << ";\n";
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
        for (const auto* klass : class_emission_order()) {
            for (const auto& method : klass->methods) {
                out << c_type_name(method->return_type) << " " << method_name(*method) << "(";
                bool wrote = false;
                if (!method->is_static) {
                    out << class_struct_name(*klass) << "* self";
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
            if (program_.entry_point->return_type == &program_.semantic_model.int_type) {
                out << "    return (int)" << method_name(*program_.entry_point) << "(hy_args);\n";
            } else {
                out << "    " << method_name(*program_.entry_point) << "(hy_args);\n";
                out << "    return 0;\n";
            }
        } else {
            if (program_.entry_point->return_type == &program_.semantic_model.int_type) {
                out << "    return (int)" << method_name(*program_.entry_point) << "();\n";
            } else {
                out << "    " << method_name(*program_.entry_point) << "();\n";
                out << "    return 0;\n";
            }
        }
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
                out << emit_variable_declaration(declaration) << ";\n";
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
            case BoundStatementKind::For: {
                const auto& for_statement = static_cast<const BoundForStatement&>(statement);
                indent(out, level);
                out << "for (";
                if (for_statement.initializer != nullptr) {
                    out << emit_for_initializer(*for_statement.initializer);
                }
                out << "; ";
                out << (for_statement.condition != nullptr ? emit_expression(*for_statement.condition) : "true");
                out << "; ";
                if (for_statement.update != nullptr) {
                    out << emit_expression(*for_statement.update);
                }
                out << ") {\n";
                emit_statement(out, *for_statement.body, level + 1);
                indent(out, level);
                out << "}\n";
                break;
            }
            case BoundStatementKind::Break:
                indent(out, level);
                out << "break;\n";
                break;
            case BoundStatementKind::Continue:
                indent(out, level);
                out << "continue;\n";
                break;
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
            case TypeKind::Enum:
                return "0";
            case TypeKind::Bool:
                return "false";
            case TypeKind::Array:
                return "(HyStringArray){0, NULL}";
            case TypeKind::String:
            case TypeKind::Class:
            case TypeKind::Interface:
            case TypeKind::TypeParameter:
            case TypeKind::Null:
            case TypeKind::Error:
                return "NULL";
            case TypeKind::Struct:
                return type->class_symbol != nullptr ? zero_helper_name(*type->class_symbol) + "()" : "NULL";
            case TypeKind::Void:
                return "";
        }
        return "NULL";
    }

    string local_name(const VariableSymbol& variable) const {
        return "local_" + sanitize_c_name(variable.name) + "_" + std::to_string(variable.id);
    }

    string emit_variable_declaration(const BoundVariableDeclarationStatement& declaration) {
        std::ostringstream builder;
        builder << c_type_name(declaration.variable->type) << " " << local_name(*declaration.variable);
        if (declaration.initializer != nullptr) {
            builder << " = " << emit_expression(*declaration.initializer);
        } else {
            builder << " = " << default_expression(declaration.variable->type);
        }
        return builder.str();
    }

    string emit_for_initializer(const BoundStatement& statement) {
        switch (statement.kind) {
            case BoundStatementKind::VariableDeclaration:
                return emit_variable_declaration(static_cast<const BoundVariableDeclarationStatement&>(statement));
            case BoundStatementKind::Expression:
                return emit_expression(*static_cast<const BoundExpressionStatement&>(statement).expression);
            default:
                return "";
        }
    }

    string emit_string_operand(const BoundExpression& expression) {
        if (expression.type == &program_.semantic_model.string_type) {
            return emit_expression(expression);
        }
        if (expression.type == &program_.semantic_model.int_type) {
            return "hy_string_from_int(" + emit_expression(expression) + ")";
        }
        if (expression.type == &program_.semantic_model.bool_type) {
            return "hy_string_from_bool(" + emit_expression(expression) + ")";
        }
        return "\"null\"";
    }

    string emit_enum_string(const BoundExpression& expression) {
        return enum_to_string_name(*expression.type->enum_symbol) + "(" + emit_expression(expression) + ")";
    }

    string emit_class_upcast(const string& expression, const ClassSymbol& source, const ClassSymbol& target) const {
        if (&source == &target) {
            return expression;
        }

        string result = expression;
        const ClassSymbol* current = &source;
        while (current != nullptr && current != &target) {
            if (current->base_class == nullptr) {
                break;
            }
            result = upcast_name(*current, *current->base_class) + "(" + result + ")";
            current = current->base_class;
        }
        return result;
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
            case BoundExpressionKind::ArrayIndex: {
                const auto& access = static_cast<const BoundArrayIndexExpression&>(expression);
                return "hy_array_index(" + emit_expression(*access.array_expression) + ", " +
                       emit_expression(*access.index_expression) + ")";
            }
            case BoundExpressionKind::StringIndex: {
                const auto& access = static_cast<const BoundStringIndexExpression&>(expression);
                return "hy_string_index(" + emit_expression(*access.string_expression) + ", " +
                       emit_expression(*access.index_expression) + ")";
            }
            case BoundExpressionKind::StringLength: {
                const auto& length = static_cast<const BoundStringLengthExpression&>(expression);
                return "hy_string_length(" + emit_expression(*length.string_expression) + ")";
            }
            case BoundExpressionKind::Assignment: {
                const auto& assignment = static_cast<const BoundAssignmentExpression&>(expression);
                return "(" + emit_expression(*assignment.target) + " = " + emit_expression(*assignment.expression) + ")";
            }
            case BoundExpressionKind::Conversion: {
                const auto& conversion = static_cast<const BoundConversionExpression&>(expression);
                if (conversion.expression != nullptr &&
                    conversion.expression->type != nullptr &&
                    conversion.expression->type->kind == TypeKind::Class &&
                    expression.type != nullptr &&
                    expression.type->kind == TypeKind::Class &&
                    conversion.expression->type->class_symbol != nullptr &&
                    expression.type->class_symbol != nullptr) {
                    return emit_class_upcast(emit_expression(*conversion.expression),
                                             *conversion.expression->type->class_symbol,
                                             *expression.type->class_symbol);
                }
                if (conversion.expression != nullptr &&
                    expression.type != nullptr &&
                    expression.type->kind == TypeKind::Interface) {
                    return "(void*)" + emit_expression(*conversion.expression);
                }
                return conversion.expression != nullptr ? emit_expression(*conversion.expression) : "NULL";
            }
            case BoundExpressionKind::Unary: {
                const auto& unary = static_cast<const BoundUnaryExpression&>(expression);
                return "(" + token_text(unary.op) + emit_expression(*unary.operand) + ")";
            }
            case BoundExpressionKind::Binary: {
                const auto& binary = static_cast<const BoundBinaryExpression&>(expression);
                if (binary.op == TokenKind::Plus && binary.type == &program_.semantic_model.string_type) {
                    return "hy_string_concat(" + emit_string_operand(*binary.left) + ", " + emit_string_operand(*binary.right) + ")";
                }
                if ((binary.op == TokenKind::EqualsEquals || binary.op == TokenKind::BangEquals) &&
                    (binary.left->type == &program_.semantic_model.string_type ||
                     binary.right->type == &program_.semantic_model.string_type)) {
                    const string comparison =
                        "hy_string_equals(" + emit_expression(*binary.left) + ", " + emit_expression(*binary.right) + ")";
                    return binary.op == TokenKind::EqualsEquals ? comparison : "(!" + comparison + ")";
                }
                return "(" + emit_expression(*binary.left) + " " + token_text(binary.op) + " " + emit_expression(*binary.right) + ")";
            }
            case BoundExpressionKind::Call: {
                const auto& call = static_cast<const BoundCallExpression&>(expression);
                if (call.method->is_builtin && call.method->owner == program_.semantic_model.console_class) {
                    if (!call.arguments.empty() &&
                        call.arguments[0]->type != nullptr &&
                        call.arguments[0]->type->kind == TypeKind::Enum &&
                        call.arguments[0]->type->enum_symbol != nullptr) {
                        const string function_name =
                            call.method->name == "Write" ? "hy_console_write_string" : "hy_console_writeline_string";
                        return function_name + "(" + emit_enum_string(*call.arguments[0]) + ")";
                    }
                    string function_name = "hy_console_writeline_string";
                    if (call.method == program_.semantic_model.console_write_string) {
                        function_name = "hy_console_write_string";
                    } else if (call.method == program_.semantic_model.console_write_int) {
                        function_name = "hy_console_write_int";
                    } else if (call.method == program_.semantic_model.console_write_bool) {
                        function_name = "hy_console_write_bool";
                    } else if (call.method == program_.semantic_model.console_writeline_int) {
                        function_name = "hy_console_writeline_int";
                    } else if (call.method == program_.semantic_model.console_writeline_bool) {
                        function_name = "hy_console_writeline_bool";
                    }
                    return function_name + "(" + emit_expression(*call.arguments[0]) + ")";
                }
                if (call.method->is_builtin && call.method->owner == program_.semantic_model.file_class) {
                    if (call.method == program_.semantic_model.file_exists) {
                        return "hy_file_exists(" + emit_expression(*call.arguments[0]) + ")";
                    }
                    if (call.method == program_.semantic_model.file_read_all_text) {
                        return "hy_file_read_all_text(" + emit_expression(*call.arguments[0]) + ")";
                    }
                    if (call.method == program_.semantic_model.file_write_all_text) {
                        return "hy_file_write_all_text(" + emit_expression(*call.arguments[0]) + ", " +
                               emit_expression(*call.arguments[1]) + ")";
                    }
                }

                if (call.dispatch_interface) {
                    std::ostringstream builder;
                    builder << interface_dispatch_name(*call.method) << "(" << emit_expression(*call.receiver);
                    for (const auto& argument : call.arguments) {
                        builder << ", " << emit_expression(*argument);
                    }
                    builder << ")";
                    return builder.str();
                }

                if (call.dispatch_virtual && call.method->virtual_root != nullptr) {
                    std::ostringstream builder;
                    builder << virtual_dispatch_name(*call.method->virtual_root) << "(";
                    if (call.dispatch_type != nullptr && call.dispatch_type->class_symbol != nullptr) {
                        builder << emit_class_upcast(emit_expression(*call.receiver),
                                                     *call.method->owner,
                                                     *call.dispatch_type->class_symbol);
                    } else {
                        builder << emit_expression(*call.receiver);
                    }
                    for (const auto& argument : call.arguments) {
                        builder << ", " << emit_expression(*argument);
                    }
                    builder << ")";
                    return builder.str();
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
                if (creation.zero_initialize && creation.class_symbol->kind == TypeKind::Struct) {
                    return zero_helper_name(*creation.class_symbol) + "()";
                }
                std::ostringstream builder;
                const int constructor_slot = creation.constructor != nullptr ? creation.constructor->slot : 0;
                builder << new_helper_name(*creation.class_symbol, constructor_slot) << "(";
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
            case TokenKind::Percent:
                return "%";
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
        return RunResult{false, std::move(diagnostics.items), 1};
    }
    if (!locate_entry_point(*program, diagnostics)) {
        return RunResult{false, std::move(diagnostics.items), 1};
    }

    Interpreter interpreter(*program);
    try {
        int exit_code = 0;
        if (!interpreter.run(options.args, &exit_code)) {
            diagnostics.add(options.input_path, 1, 1, "Interpreter could not start the program");
            return RunResult{false, std::move(diagnostics.items), 1};
        }
        return RunResult{true, {}, exit_code};
    } catch (const std::exception& ex) {
        diagnostics.add(options.input_path, 1, 1, "Runtime error: " + string(ex.what()));
        return RunResult{false, std::move(diagnostics.items), 1};
    }
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
