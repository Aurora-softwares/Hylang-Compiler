using Hydrogen.Compiler.Diagnostics;

namespace Hydrogen.Compiler.Syntax {
    public class AstParser {
        private SyntaxTokenList tokens;
        private DiagnosticBag diagnostics;
        private int index;

        public AstParser(SyntaxTokenList inputTokens, DiagnosticBag inputDiagnostics) {
            tokens = inputTokens;
            diagnostics = inputDiagnostics;
            index = 0;
        }

        public CompilationUnitSyntax ParseCompilationUnit() {
            UsingDirectiveSyntax[] usings = ParseUsingDirectives();
            NamespaceDeclarationSyntax[] namespaces = new NamespaceDeclarationSyntax[0];
            int namespaceCount = 0;
            ClassDeclarationSyntax[] classes = new ClassDeclarationSyntax[0];
            int classCount = 0;

            while (!Check(SyntaxKind.EndOfFileToken)) {
                SkipModifiers();
                if (Check(SyntaxKind.NamespaceKeyword)) {
                    namespaces = AppendNamespace(namespaces, namespaceCount, ParseNamespace());
                    namespaceCount = namespaceCount + 1;
                    continue;
                }
                if (Check(SyntaxKind.ClassKeyword)) {
                    classes = AppendClass(classes, classCount, ParseClass());
                    classCount = classCount + 1;
                    continue;
                }
                diagnostics.Report(Current().Line(), Current().Column(), "Expected namespace or class declaration");
                Advance();
            }
            Consume(SyntaxKind.EndOfFileToken, "Expected end of file");
            return new CompilationUnitSyntax(usings, namespaces, classes);
        }

        private UsingDirectiveSyntax[] ParseUsingDirectives() {
            UsingDirectiveSyntax[] items = new UsingDirectiveSyntax[0];
            int count = 0;
            while (Check(SyntaxKind.UsingKeyword)) {
                Consume(SyntaxKind.UsingKeyword, "Expected using");
                string name = ParseQualifiedNameText();
                Consume(SyntaxKind.SemicolonToken, "Expected ';' after using");
                items = AppendUsing(items, count, new UsingDirectiveSyntax(name));
                count = count + 1;
            }
            return items;
        }

        private NamespaceDeclarationSyntax ParseNamespace() {
            Consume(SyntaxKind.NamespaceKeyword, "Expected namespace");
            string name = ParseQualifiedNameText();
            Consume(SyntaxKind.OpenBraceToken, "Expected '{' after namespace");
            ClassDeclarationSyntax[] classes = new ClassDeclarationSyntax[0];
            int classCount = 0;
            while (!Check(SyntaxKind.CloseBraceToken) && !Check(SyntaxKind.EndOfFileToken)) {
                SkipModifiers();
                if (Check(SyntaxKind.ClassKeyword)) {
                    classes = AppendClass(classes, classCount, ParseClass());
                    classCount = classCount + 1;
                    continue;
                }
                diagnostics.Report(Current().Line(), Current().Column(), "Expected class declaration");
                Advance();
            }
            Consume(SyntaxKind.CloseBraceToken, "Expected '}' after namespace");
            return new NamespaceDeclarationSyntax(name, classes);
        }

        private ClassDeclarationSyntax ParseClass() {
            Consume(SyntaxKind.ClassKeyword, "Expected class");
            string name = ConsumeIdentifier("Expected class name");
            // Skip base list / type parameters in stage1 AST (subset avoids them).
            if (Check(SyntaxKind.LessToken)) {
                diagnostics.Report(Current().Line(), Current().Column(), "not supported in self-host subset: generics");
                SkipTypeArgumentOrParameterList();
            }
            if (Check(SyntaxKind.ColonToken)) {
                // Parse and ignore base list; subset will reject in binder later if needed.
                Advance();
                ParseQualifiedNameText();
            }
            Consume(SyntaxKind.OpenBraceToken, "Expected '{' after class");
            MethodDeclarationSyntax[] methods = ParseClassMembers();
            Consume(SyntaxKind.CloseBraceToken, "Expected '}' after class");
            return new ClassDeclarationSyntax(name, methods);
        }

        private MethodDeclarationSyntax[] ParseClassMembers() {
            MethodDeclarationSyntax[] methods = new MethodDeclarationSyntax[0];
            int count = 0;
            while (!Check(SyntaxKind.CloseBraceToken) && !Check(SyntaxKind.EndOfFileToken)) {
                bool isStatic = false;
                while (SyntaxFacts.IsModifier(Current().Kind())) {
                    if (Current().Kind() == SyntaxKind.StaticKeyword) {
                        isStatic = true;
                    }
                    Advance();
                }

                TypeSyntax returnType = ParseType();
                string name = "";
                if (Check(SyntaxKind.IdentifierToken)) {
                    name = ConsumeIdentifier("Expected member name");
                    if (Check(SyntaxKind.OpenParenToken)) {
                        ParameterSyntax[] parameters = ParseParameterList();
                        StatementSyntax body = ParseBlock();
                        methods = AppendMethod(methods, count, new MethodDeclarationSyntax(name, isStatic, returnType, parameters, body));
                        count = count + 1;
                        continue;
                    }
                } else if (Check(SyntaxKind.OpenParenToken)) {
                    // Constructor: no explicit return type. Treat as void-returning method named after the type.
                    ParameterSyntax[] parameters2 = ParseParameterList();
                    StatementSyntax body2 = ParseBlock();
                    methods = AppendMethod(methods, count, new MethodDeclarationSyntax(returnType.DisplayName(), false, new TypeSyntax("void"), parameters2, body2));
                    count = count + 1;
                    continue;
                } else {
                    Consume(SyntaxKind.IdentifierToken, "Expected member name");
                }

                // Field: skip until semicolon.
                while (!Check(SyntaxKind.SemicolonToken) && !Check(SyntaxKind.EndOfFileToken)) {
                    Advance();
                }
                Consume(SyntaxKind.SemicolonToken, "Expected ';' after field");
            }
            return methods;
        }

        private ParameterSyntax[] ParseParameterList() {
            Consume(SyntaxKind.OpenParenToken, "Expected '('");
            ParameterSyntax[] items = new ParameterSyntax[0];
            int count = 0;
            if (!Check(SyntaxKind.CloseParenToken)) {
                while (true) {
                    TypeSyntax type = ParseType();
                    string name = ConsumeIdentifier("Expected parameter name");
                    items = AppendParameter(items, count, new ParameterSyntax(type, name));
                    count = count + 1;
                    if (Check(SyntaxKind.CommaToken)) {
                        Advance();
                        continue;
                    }
                    break;
                }
            }
            Consume(SyntaxKind.CloseParenToken, "Expected ')'");
            return items;
        }

        private StatementSyntax ParseBlock() {
            Consume(SyntaxKind.OpenBraceToken, "Expected '{'");
            StatementSyntax[] items = new StatementSyntax[0];
            int count = 0;
            while (!Check(SyntaxKind.CloseBraceToken) && !Check(SyntaxKind.EndOfFileToken)) {
                StatementSyntax statement = ParseStatement();
                items = AppendStatement(items, count, statement);
                count = count + 1;
            }
            Consume(SyntaxKind.CloseBraceToken, "Expected '}'");
            return StatementSyntax.Block(items);
        }

        private StatementSyntax ParseStatement() {
            if (Check(SyntaxKind.OpenBraceToken)) {
                return ParseBlock();
            }
            if (Check(SyntaxKind.IfKeyword)) {
                return ParseIf();
            }
            if (Check(SyntaxKind.WhileKeyword)) {
                return ParseWhile();
            }
            if (Check(SyntaxKind.ReturnKeyword)) {
                return ParseReturn();
            }

            // local declaration: <type|var> <id> [= expr] ;
            if (LooksLikeLocalDeclaration()) {
                TypeSyntax type = ParseType();
                string name = ConsumeIdentifier("Expected identifier after type");
                ExpressionSyntax initializer = null;
                if (Check(SyntaxKind.EqualsToken)) {
                    Advance();
                    initializer = ParseExpression();
                }
                Consume(SyntaxKind.SemicolonToken, "Expected ';' after declaration");
                return StatementSyntax.VariableDeclaration(type, name, initializer);
            }

            ExpressionSyntax expr = ParseExpression();
            Consume(SyntaxKind.SemicolonToken, "Expected ';' after expression");
            return StatementSyntax.ExpressionStatement(expr);
        }

        private bool LooksLikeLocalDeclaration() {
            // We only treat a statement as a declaration if a type-like sequence is followed by an identifier.
            int offset = 0;
            SyntaxKind kind = Peek(offset).Kind();
            if (!IsTypeStart(kind)) {
                return false;
            }

            // consume type start
            offset = offset + 1;

            // qualified name segments
            while (Peek(offset).Kind() == SyntaxKind.DotToken) {
                if (Peek(offset + 1).Kind() != SyntaxKind.IdentifierToken) {
                    return false;
                }
                offset = offset + 2;
            }

            // optional array brackets
            if (Peek(offset).Kind() == SyntaxKind.OpenBracketToken && Peek(offset + 1).Kind() == SyntaxKind.CloseBracketToken) {
                offset = offset + 2;
            }

            // now must be an identifier (the variable name)
            return Peek(offset).Kind() == SyntaxKind.IdentifierToken;
        }

        private StatementSyntax ParseIf() {
            Consume(SyntaxKind.IfKeyword, "Expected if");
            Consume(SyntaxKind.OpenParenToken, "Expected '(' after if");
            ExpressionSyntax condition = ParseExpression();
            Consume(SyntaxKind.CloseParenToken, "Expected ')' after if condition");
            StatementSyntax thenStatement = ParseStatement();
            StatementSyntax elseStatement = null;
            if (Check(SyntaxKind.ElseKeyword)) {
                Advance();
                elseStatement = ParseStatement();
            }
            return StatementSyntax.If(condition, thenStatement, elseStatement);
        }

        private StatementSyntax ParseWhile() {
            Consume(SyntaxKind.WhileKeyword, "Expected while");
            Consume(SyntaxKind.OpenParenToken, "Expected '(' after while");
            ExpressionSyntax condition = ParseExpression();
            Consume(SyntaxKind.CloseParenToken, "Expected ')' after while condition");
            StatementSyntax body = ParseStatement();
            return StatementSyntax.While(condition, body);
        }

        private StatementSyntax ParseReturn() {
            Consume(SyntaxKind.ReturnKeyword, "Expected return");
            ExpressionSyntax expression = null;
            if (!Check(SyntaxKind.SemicolonToken)) {
                expression = ParseExpression();
            }
            Consume(SyntaxKind.SemicolonToken, "Expected ';' after return");
            return StatementSyntax.Return(expression);
        }

        private ExpressionSyntax ParseExpression() {
            return ParseAssignment();
        }

        private ExpressionSyntax ParseAssignment() {
            ExpressionSyntax left = ParseBinaryExpression(0);
            if (Check(SyntaxKind.EqualsToken)) {
                Advance();
                ExpressionSyntax right = ParseAssignment();
                return ExpressionSyntax.Assignment(left, right);
            }
            return left;
        }

        private ExpressionSyntax ParseBinaryExpression(int parentPrecedence) {
            ExpressionSyntax left = ParseUnary();
            while (true) {
                int precedence = BinaryPrecedence(Current().Kind());
                if (precedence == 0 || precedence <= parentPrecedence) {
                    break;
                }
                SyntaxKind op = Advance().Kind();
                ExpressionSyntax right = ParseBinaryExpression(precedence);
                left = ExpressionSyntax.Binary(left, op, right);
            }
            return left;
        }

        private ExpressionSyntax ParseUnary() {
            if (Check(SyntaxKind.BangToken) || Check(SyntaxKind.MinusToken)) {
                SyntaxKind op = Advance().Kind();
                ExpressionSyntax operand = ParseUnary();
                return ExpressionSyntax.Unary(op, operand);
            }
            return ParsePostfix();
        }

        private ExpressionSyntax ParsePostfix() {
            ExpressionSyntax expr = ParsePrimary();
            while (true) {
                if (Check(SyntaxKind.DotToken)) {
                    Advance();
                    string name = ConsumeIdentifier("Expected member name");
                    expr = ExpressionSyntax.MemberAccess(expr, name);
                    continue;
                }
                if (Check(SyntaxKind.OpenParenToken)) {
                    ExpressionSyntax[] args = ParseArgumentList();
                    expr = ExpressionSyntax.Invocation(expr, args);
                    continue;
                }
                if (Check(SyntaxKind.OpenBracketToken)) {
                    Advance();
                    ExpressionSyntax indexExpr = ParseExpression();
                    Consume(SyntaxKind.CloseBracketToken, "Expected ']'");
                    expr = ExpressionSyntax.IndexExpr(expr, indexExpr);
                    continue;
                }
                break;
            }
            return expr;
        }

        private ExpressionSyntax[] ParseArgumentList() {
            Consume(SyntaxKind.OpenParenToken, "Expected '('");
            ExpressionSyntax[] items = new ExpressionSyntax[0];
            int count = 0;
            if (!Check(SyntaxKind.CloseParenToken)) {
                while (true) {
                    ExpressionSyntax arg = ParseExpression();
                    items = AppendExpression(items, count, arg);
                    count = count + 1;
                    if (Check(SyntaxKind.CommaToken)) {
                        Advance();
                        continue;
                    }
                    break;
                }
            }
            Consume(SyntaxKind.CloseParenToken, "Expected ')'");
            return items;
        }

        private ExpressionSyntax ParsePrimary() {
            if (Check(SyntaxKind.OpenParenToken) && LooksLikeCastExpression()) {
                Advance();
                TypeSyntax type = ParseType();
                Consume(SyntaxKind.CloseParenToken, "Expected ')'");
                ExpressionSyntax operand = ParsePrimary();
                return ExpressionSyntax.Cast(type, operand);
            }
            if (Check(SyntaxKind.OpenParenToken)) {
                Advance();
                ExpressionSyntax inner = ParseExpression();
                Consume(SyntaxKind.CloseParenToken, "Expected ')'");
                return inner;
            }
            if (Check(SyntaxKind.StringToken)) {
                string tokenText = Advance().Text();
                string text = UnquoteStringToken(tokenText);
                return ExpressionSyntax.Literal("string", text);
            }
            if (Check(SyntaxKind.NumberToken)) {
                string text = Advance().Text();
                return ExpressionSyntax.Literal("number", text);
            }
            if (Check(SyntaxKind.TrueKeyword)) {
                Advance();
                return ExpressionSyntax.Literal("bool", "true");
            }
            if (Check(SyntaxKind.FalseKeyword)) {
                Advance();
                return ExpressionSyntax.Literal("bool", "false");
            }
            if (Check(SyntaxKind.NullKeyword)) {
                Advance();
                return ExpressionSyntax.Literal("null", "null");
            }
            if (Check(SyntaxKind.NewKeyword)) {
                Advance();
                TypeSyntax type = ParseType();
                if (Check(SyntaxKind.OpenBracketToken)) {
                    Advance();
                    ExpressionSyntax size = ParseExpression();
                    Consume(SyntaxKind.CloseBracketToken, "Expected ']'");
                    return ExpressionSyntax.ArrayCreation(type, size);
                }
                // Allow constructor arguments (Stage1B parser support). Binder/codegen may still restrict semantics.
                ExpressionSyntax[] ctorArgs = ParseArgumentList();
                return ExpressionSyntax.ObjectCreation(type);
            }
            if (Current().Kind() == SyntaxKind.IdentifierToken) {
                return ExpressionSyntax.NameExpr(Advance().Text());
            }

            diagnostics.Report(Current().Line(), Current().Column(), "Expected expression");
            // Ensure we always make progress to avoid infinite loops on unexpected tokens.
            Advance();
            return ExpressionSyntax.NameExpr("");
        }

        private bool LooksLikeCastExpression() {
            // Heuristic: ( <type> ) <primary-start>
            if (Peek(0).Kind() != SyntaxKind.OpenParenToken) { return false; }
            if (!IsTypeStart(Peek(1).Kind())) { return false; }

            // Find the closing paren after a simple type (qualified name + optional [] only).
            int offset = 1;
            // consume qualified name / predefined type
            offset = offset + 1;
            while (Peek(offset).Kind() == SyntaxKind.DotToken && Peek(offset + 1).Kind() == SyntaxKind.IdentifierToken) {
                offset = offset + 2;
            }
            if (Peek(offset).Kind() == SyntaxKind.OpenBracketToken && Peek(offset + 1).Kind() == SyntaxKind.CloseBracketToken) {
                offset = offset + 2;
            }
            if (Peek(offset).Kind() != SyntaxKind.CloseParenToken) { return false; }

            SyntaxKind next = Peek(offset + 1).Kind();
            return next == SyntaxKind.IdentifierToken ||
                   next == SyntaxKind.StringToken ||
                   next == SyntaxKind.NumberToken ||
                   next == SyntaxKind.TrueKeyword ||
                   next == SyntaxKind.FalseKeyword ||
                   next == SyntaxKind.NullKeyword ||
                   next == SyntaxKind.NewKeyword ||
                   next == SyntaxKind.OpenParenToken;
        }

        private string UnquoteStringToken(string tokenText) {
            // Lexer includes surrounding quotes. Keep this bootstrap parser simple:
            // strip one leading/trailing quote if present; leave escape sequences as-is.
            if (tokenText.Length >= 2 && tokenText[0] == "\"" && tokenText[tokenText.Length - 1] == "\"") {
                return Slice(tokenText, 1, tokenText.Length - 2);
            }
            return tokenText;
        }

        private string Slice(string text, int start, int length) {
            string result = "";
            int i = 0;
            while (i < length && start + i < text.Length) {
                result = result + text[start + i];
                i = i + 1;
            }
            return result;
        }

        private TypeSyntax ParseType() {
            string name = "";
            if (IsPredefinedType(Current().Kind())) {
                name = Advance().Text();
            } else {
                name = ParseQualifiedNameText();
            }

            if (Check(SyntaxKind.OpenBracketToken)) {
                Advance();
                Consume(SyntaxKind.CloseBracketToken, "Expected ']'");
                name = name + "[]";
            }
            return new TypeSyntax(name);
        }

        private bool IsPredefinedType(SyntaxKind kind) {
            return kind == SyntaxKind.VoidKeyword ||
                   kind == SyntaxKind.BoolKeyword ||
                   kind == SyntaxKind.ByteKeyword ||
                   kind == SyntaxKind.SByteKeyword ||
                   kind == SyntaxKind.ShortKeyword ||
                   kind == SyntaxKind.UShortKeyword ||
                   kind == SyntaxKind.IntKeyword ||
                   kind == SyntaxKind.UIntKeyword ||
                   kind == SyntaxKind.LongKeyword ||
                   kind == SyntaxKind.ULongKeyword ||
                   kind == SyntaxKind.NIntKeyword ||
                   kind == SyntaxKind.NUIntKeyword ||
                   kind == SyntaxKind.StringKeyword ||
                   kind == SyntaxKind.VarKeyword;
        }

        private bool IsTypeStart(SyntaxKind kind) {
            return IsPredefinedType(kind) || kind == SyntaxKind.IdentifierToken;
        }

        private string ParseQualifiedNameText() {
            string text = ConsumeIdentifier("Expected identifier");
            while (Check(SyntaxKind.DotToken)) {
                Advance();
                text = text + "." + ConsumeIdentifier("Expected identifier");
            }
            return text;
        }

        private void SkipModifiers() {
            while (SyntaxFacts.IsModifier(Current().Kind())) {
                Advance();
            }
        }

        private void SkipTypeArgumentOrParameterList() {
            if (!Check(SyntaxKind.LessToken)) {
                return;
            }
            int depth = 0;
            while (!Check(SyntaxKind.EndOfFileToken)) {
                if (Check(SyntaxKind.LessToken)) { depth = depth + 1; }
                if (Check(SyntaxKind.GreaterToken)) { depth = depth - 1; }
                Advance();
                if (depth == 0) { return; }
            }
        }

        private int BinaryPrecedence(SyntaxKind kind) {
            if (kind == SyntaxKind.StarToken || kind == SyntaxKind.SlashToken || kind == SyntaxKind.PercentToken) { return 6; }
            if (kind == SyntaxKind.PlusToken || kind == SyntaxKind.MinusToken) { return 5; }
            if (kind == SyntaxKind.LessToken || kind == SyntaxKind.LessEqualsToken ||
                kind == SyntaxKind.GreaterToken || kind == SyntaxKind.GreaterEqualsToken) { return 4; }
            if (kind == SyntaxKind.EqualsEqualsToken || kind == SyntaxKind.BangEqualsToken) { return 3; }
            if (kind == SyntaxKind.AmpersandAmpersandToken) { return 2; }
            if (kind == SyntaxKind.PipePipeToken) { return 1; }
            return 0;
        }

        private SyntaxToken Current() {
            return Peek(0);
        }

        private SyntaxToken Peek(int offset) {
            int target = index + offset;
            if (target >= tokens.Count()) {
                return tokens.Get(tokens.Count() - 1);
            }
            return tokens.Get(target);
        }

        private bool Check(SyntaxKind kind) {
            return Current().Kind() == kind;
        }

        private SyntaxToken Advance() {
            SyntaxToken token = Current();
            if (!Check(SyntaxKind.EndOfFileToken)) {
                index = index + 1;
            }
            return token;
        }

        private SyntaxToken Consume(SyntaxKind kind, string message) {
            if (Check(kind)) {
                return Advance();
            }
            diagnostics.Report(Current().Line(), Current().Column(), message);
            return new SyntaxToken(kind, "", Current().Line(), Current().Column(), Current().Position());
        }

        private string ConsumeIdentifier(string message) {
            if (Current().Kind() == SyntaxKind.IdentifierToken) {
                return Advance().Text();
            }
            diagnostics.Report(Current().Line(), Current().Column(), message);
            return "";
        }

        private UsingDirectiveSyntax[] AppendUsing(UsingDirectiveSyntax[] items, int count, UsingDirectiveSyntax item) {
            UsingDirectiveSyntax[] next = new UsingDirectiveSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private NamespaceDeclarationSyntax[] AppendNamespace(NamespaceDeclarationSyntax[] items, int count, NamespaceDeclarationSyntax item) {
            NamespaceDeclarationSyntax[] next = new NamespaceDeclarationSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private ClassDeclarationSyntax[] AppendClass(ClassDeclarationSyntax[] items, int count, ClassDeclarationSyntax item) {
            ClassDeclarationSyntax[] next = new ClassDeclarationSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private MethodDeclarationSyntax[] AppendMethod(MethodDeclarationSyntax[] items, int count, MethodDeclarationSyntax item) {
            MethodDeclarationSyntax[] next = new MethodDeclarationSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private ParameterSyntax[] AppendParameter(ParameterSyntax[] items, int count, ParameterSyntax item) {
            ParameterSyntax[] next = new ParameterSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private StatementSyntax[] AppendStatement(StatementSyntax[] items, int count, StatementSyntax item) {
            StatementSyntax[] next = new StatementSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private ExpressionSyntax[] AppendExpression(ExpressionSyntax[] items, int count, ExpressionSyntax item) {
            ExpressionSyntax[] next = new ExpressionSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }
    }
}
