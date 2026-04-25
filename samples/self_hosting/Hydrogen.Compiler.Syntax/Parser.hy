using Hydrogen.Compiler.Diagnostics;
using Hydrogen.Compiler.Text;
using System.Collections;

namespace Hydrogen.Compiler.Syntax {
    public class Parser {
        private List<SyntaxToken> tokens;
        private DiagnosticBag diagnostics;
        private int index;
        private string output;
        private int indent;

        public Parser(List<SyntaxToken> inputTokens, DiagnosticBag inputDiagnostics) {
            tokens = inputTokens;
            diagnostics = inputDiagnostics;
            index = 0;
            output = "";
            indent = 0;
        }

        public string ParseCompilationUnit() {
            Emit("CompilationUnit");
            Push();
            while (!Check(SyntaxKind.EndOfFileToken)) {
                if (Check(SyntaxKind.UsingKeyword)) {
                    ParseUsingDirective();
                } else {
                    ParseNamespaceMember();
                }
            }
            EmitToken(Consume(SyntaxKind.EndOfFileToken, "Expected end of file"));
            Pop();
            return output;
        }

        private void ParseUsingDirective() {
            Emit("UsingDirective");
            Push();
            EmitToken(Consume(SyntaxKind.UsingKeyword, "Expected using keyword"));
            ParseQualifiedName();
            EmitToken(Consume(SyntaxKind.SemicolonToken, "Expected ';' after using directive"));
            Pop();
        }

        private void ParseNamespaceMember() {
            SkipModifiers();
            if (Check(SyntaxKind.NamespaceKeyword)) {
                ParseNamespaceDeclaration();
                return;
            }
            if (SyntaxFacts.IsTypeDeclarationStart(Current().Kind())) {
                ParseTypeDeclaration();
                return;
            }
            diagnostics.Report(Current().Line(), Current().Column(), "Expected namespace or type declaration");
            EmitToken(Advance());
        }

        private void ParseNamespaceDeclaration() {
            Emit("NamespaceDeclaration");
            Push();
            EmitToken(Consume(SyntaxKind.NamespaceKeyword, "Expected namespace keyword"));
            ParseQualifiedName();
            EmitToken(Consume(SyntaxKind.OpenBraceToken, "Expected '{' after namespace name"));
            while (!Check(SyntaxKind.CloseBraceToken) && !Check(SyntaxKind.EndOfFileToken)) {
                ParseNamespaceMember();
            }
            EmitToken(Consume(SyntaxKind.CloseBraceToken, "Expected '}' after namespace"));
            Pop();
        }

        private void ParseTypeDeclaration() {
            SyntaxKind kind = Current().Kind();
            if (kind == SyntaxKind.EnumKeyword) {
                ParseEnumDeclaration();
                return;
            }
            string name = SyntaxFacts.KindName(kind) + "Declaration";
            Emit(name);
            Push();
            EmitToken(Advance());
            EmitToken(Consume(SyntaxKind.IdentifierToken, "Expected type name"));
            ParseOptionalTypeParameters();
            if (Match(SyntaxKind.ColonToken)) {
                Emit("BaseList");
                Push();
                ParseTypeSyntax();
                while (Match(SyntaxKind.CommaToken)) {
                    ParseTypeSyntax();
                }
                Pop();
            }
            EmitToken(Consume(SyntaxKind.OpenBraceToken, "Expected '{' in type declaration"));
            while (!Check(SyntaxKind.CloseBraceToken) && !Check(SyntaxKind.EndOfFileToken)) {
                ParseMemberDeclaration();
            }
            EmitToken(Consume(SyntaxKind.CloseBraceToken, "Expected '}' in type declaration"));
            Pop();
        }

        private void ParseEnumDeclaration() {
            Emit("EnumDeclaration");
            Push();
            EmitToken(Consume(SyntaxKind.EnumKeyword, "Expected enum keyword"));
            EmitToken(Consume(SyntaxKind.IdentifierToken, "Expected enum name"));
            EmitToken(Consume(SyntaxKind.OpenBraceToken, "Expected '{' in enum declaration"));
            while (!Check(SyntaxKind.CloseBraceToken) && !Check(SyntaxKind.EndOfFileToken)) {
                Emit("EnumMember");
                Push();
                EmitToken(Consume(SyntaxKind.IdentifierToken, "Expected enum member name"));
                if (Check(SyntaxKind.CommaToken)) {
                    EmitToken(Advance());
                }
                Pop();
            }
            EmitToken(Consume(SyntaxKind.CloseBraceToken, "Expected '}' in enum declaration"));
            Pop();
        }

        private void ParseMemberDeclaration() {
            SkipModifiers();
            if (Check(SyntaxKind.IdentifierToken) && Peek(1).Kind() == SyntaxKind.OpenParenToken) {
                ParseConstructorDeclaration();
                return;
            }
            Emit("MemberDeclaration");
            Push();
            ParseTypeSyntax();
            EmitToken(Consume(SyntaxKind.IdentifierToken, "Expected member name"));
            ParseOptionalTypeParameters();
            if (Check(SyntaxKind.OpenParenToken)) {
                ParseParameterList();
                if (Match(SyntaxKind.ColonToken)) {
                    Emit("ConstructorInitializer");
                    Push();
                    ParseExpression();
                    Pop();
                }
                ParseBlockOrSemicolon();
            } else {
                if (Match(SyntaxKind.EqualsToken)) {
                    ParseExpression();
                }
                EmitToken(Consume(SyntaxKind.SemicolonToken, "Expected ';' after field declaration"));
            }
            Pop();
        }

        private void ParseConstructorDeclaration() {
            Emit("ConstructorDeclaration");
            Push();
            EmitToken(Consume(SyntaxKind.IdentifierToken, "Expected constructor name"));
            ParseParameterList();
            if (Match(SyntaxKind.ColonToken)) {
                Emit("ConstructorInitializer");
                Push();
                ParseExpression();
                Pop();
            }
            ParseBlockOrSemicolon();
            Pop();
        }

        private void ParseParameterList() {
            Emit("ParameterList");
            Push();
            EmitToken(Consume(SyntaxKind.OpenParenToken, "Expected '('"));
            while (!Check(SyntaxKind.CloseParenToken) && !Check(SyntaxKind.EndOfFileToken)) {
                Emit("Parameter");
                Push();
                ParseTypeSyntax();
                EmitToken(Consume(SyntaxKind.IdentifierToken, "Expected parameter name"));
                Pop();
                if (!Match(SyntaxKind.CommaToken)) {
                    break;
                }
            }
            EmitToken(Consume(SyntaxKind.CloseParenToken, "Expected ')'"));
            Pop();
        }

        private void ParseBlockOrSemicolon() {
            if (Check(SyntaxKind.SemicolonToken)) {
                EmitToken(Advance());
                return;
            }
            ParseBlock();
        }

        private void ParseBlock() {
            Emit("BlockStatement");
            Push();
            EmitToken(Consume(SyntaxKind.OpenBraceToken, "Expected '{'"));
            while (!Check(SyntaxKind.CloseBraceToken) && !Check(SyntaxKind.EndOfFileToken)) {
                ParseStatement();
            }
            EmitToken(Consume(SyntaxKind.CloseBraceToken, "Expected '}'"));
            Pop();
        }

        private void ParseStatement() {
            if (Check(SyntaxKind.OpenBraceToken)) {
                ParseBlock();
                return;
            }
            if (Check(SyntaxKind.IfKeyword)) {
                ParseIfStatement();
                return;
            }
            if (Check(SyntaxKind.WhileKeyword)) {
                ParseWhileStatement();
                return;
            }
            if (Check(SyntaxKind.ForKeyword)) {
                ParseForStatement();
                return;
            }
            if (Check(SyntaxKind.BreakKeyword) || Check(SyntaxKind.ContinueKeyword)) {
                Emit("JumpStatement");
                Push();
                EmitToken(Advance());
                EmitToken(Consume(SyntaxKind.SemicolonToken, "Expected ';' after jump statement"));
                Pop();
                return;
            }
            if (Check(SyntaxKind.ReturnKeyword)) {
                ParseReturnStatement();
                return;
            }
            if (Check(SyntaxKind.UnsafeKeyword)) {
                ParseUnsafeStatement();
                return;
            }
            if (LooksLikeLocalDeclaration()) {
                ParseLocalDeclaration();
                return;
            }
            ParseExpressionStatement();
        }

        private void ParseIfStatement() {
            Emit("IfStatement");
            Push();
            EmitToken(Consume(SyntaxKind.IfKeyword, "Expected if"));
            ParseParenthesizedExpression();
            ParseStatement();
            if (Check(SyntaxKind.ElseKeyword)) {
                EmitToken(Advance());
                ParseStatement();
            }
            Pop();
        }

        private void ParseWhileStatement() {
            Emit("WhileStatement");
            Push();
            EmitToken(Consume(SyntaxKind.WhileKeyword, "Expected while"));
            ParseParenthesizedExpression();
            ParseStatement();
            Pop();
        }

        private void ParseForStatement() {
            Emit("ForStatement");
            Push();
            EmitToken(Consume(SyntaxKind.ForKeyword, "Expected for"));
            EmitToken(Consume(SyntaxKind.OpenParenToken, "Expected '(' after for"));
            if (!Check(SyntaxKind.SemicolonToken)) {
                if (LooksLikeLocalDeclaration()) {
                    ParseLocalDeclaration();
                } else {
                    ParseExpression();
                    EmitToken(Consume(SyntaxKind.SemicolonToken, "Expected ';' after for initializer"));
                }
            } else {
                EmitToken(Advance());
            }
            if (!Check(SyntaxKind.SemicolonToken)) {
                ParseExpression();
            }
            EmitToken(Consume(SyntaxKind.SemicolonToken, "Expected ';' after for condition"));
            if (!Check(SyntaxKind.CloseParenToken)) {
                ParseExpression();
            }
            EmitToken(Consume(SyntaxKind.CloseParenToken, "Expected ')' after for clauses"));
            ParseStatement();
            Pop();
        }

        private void ParseReturnStatement() {
            Emit("ReturnStatement");
            Push();
            EmitToken(Consume(SyntaxKind.ReturnKeyword, "Expected return"));
            if (!Check(SyntaxKind.SemicolonToken)) {
                ParseExpression();
            }
            EmitToken(Consume(SyntaxKind.SemicolonToken, "Expected ';' after return"));
            Pop();
        }

        private void ParseUnsafeStatement() {
            Emit("UnsafeStatement");
            Push();
            EmitToken(Consume(SyntaxKind.UnsafeKeyword, "Expected unsafe"));
            ParseBlock();
            Pop();
        }

        private void ParseLocalDeclaration() {
            Emit("LocalDeclaration");
            Push();
            ParseTypeSyntax();
            EmitToken(Consume(SyntaxKind.IdentifierToken, "Expected local name"));
            if (Match(SyntaxKind.EqualsToken)) {
                ParseExpression();
            }
            EmitToken(Consume(SyntaxKind.SemicolonToken, "Expected ';' after local declaration"));
            Pop();
        }

        private void ParseExpressionStatement() {
            Emit("ExpressionStatement");
            Push();
            ParseExpression();
            EmitToken(Consume(SyntaxKind.SemicolonToken, "Expected ';' after expression"));
            Pop();
        }

        private void ParseExpression() {
            ParseAssignmentExpression();
        }

        private void ParseAssignmentExpression() {
            Emit("Expression");
            Push();
            ParseBinaryExpression(0);
            if (Match(SyntaxKind.EqualsToken)) {
                Emit("AssignmentTail");
                Push();
                ParseAssignmentExpression();
                Pop();
            }
            Pop();
        }

        private void ParseBinaryExpression(int parentPrecedence) {
            int unaryPrecedence = UnaryPrecedence(Current().Kind());
            if (unaryPrecedence != 0 && unaryPrecedence >= parentPrecedence) {
                Emit("UnaryExpression " + SyntaxFacts.KindName(Current().Kind()));
                Push();
                EmitToken(Advance());
                ParseBinaryExpression(unaryPrecedence);
                Pop();
            } else {
                ParsePostfixExpression();
            }

            while (true) {
                int precedence = BinaryPrecedence(Current().Kind());
                if (precedence == 0 || precedence <= parentPrecedence) {
                    return;
                }
                Emit("BinaryOperator " + SyntaxFacts.KindName(Current().Kind()));
                Push();
                EmitToken(Advance());
                ParseBinaryExpression(precedence);
                Pop();
            }
        }

        private void ParsePostfixExpression() {
            ParsePrimaryExpression();
            while (true) {
                if (Match(SyntaxKind.DotToken)) {
                    Emit("MemberAccessExpression");
                    Push();
                    EmitToken(Consume(SyntaxKind.IdentifierToken, "Expected member name"));
                    Pop();
                    continue;
                }
                if (Check(SyntaxKind.OpenParenToken)) {
                    ParseArgumentList();
                    continue;
                }
                if (Match(SyntaxKind.OpenBracketToken)) {
                    Emit("ElementAccessExpression");
                    Push();
                    ParseExpression();
                    EmitToken(Consume(SyntaxKind.CloseBracketToken, "Expected ']'"));
                    Pop();
                    continue;
                }
                return;
            }
        }

        private void ParsePrimaryExpression() {
            if (Check(SyntaxKind.OpenParenToken)) {
                ParseParenthesizedExpression();
                return;
            }
            if (Check(SyntaxKind.NewKeyword)) {
                Emit("ObjectOrArrayCreationExpression");
                Push();
                EmitToken(Advance());
                ParseTypeSyntax();
                if (Check(SyntaxKind.OpenParenToken)) {
                    ParseArgumentList();
                }
                if (Check(SyntaxKind.OpenBracketToken)) {
                    EmitToken(Advance());
                    ParseExpression();
                    EmitToken(Consume(SyntaxKind.CloseBracketToken, "Expected ']'"));
                }
                Pop();
                return;
            }
            if (Check(SyntaxKind.SizeOfKeyword)) {
                Emit("SizeOfExpression");
                Push();
                EmitToken(Advance());
                EmitToken(Consume(SyntaxKind.OpenParenToken, "Expected '(' after sizeof"));
                ParseTypeSyntax();
                EmitToken(Consume(SyntaxKind.CloseParenToken, "Expected ')' after sizeof"));
                Pop();
                return;
            }
            if (Check(SyntaxKind.StackAllocKeyword)) {
                Emit("StackAllocExpression");
                Push();
                EmitToken(Advance());
                ParseStackAllocTypeSyntax();
                EmitToken(Consume(SyntaxKind.OpenBracketToken, "Expected '[' after stackalloc type"));
                ParseExpression();
                EmitToken(Consume(SyntaxKind.CloseBracketToken, "Expected ']'"));
                Pop();
                return;
            }
            Emit("PrimaryExpression");
            Push();
            EmitToken(Advance());
            Pop();
        }

        private void ParseParenthesizedExpression() {
            Emit("ParenthesizedExpression");
            Push();
            EmitToken(Consume(SyntaxKind.OpenParenToken, "Expected '('"));
            ParseExpression();
            EmitToken(Consume(SyntaxKind.CloseParenToken, "Expected ')'"));
            Pop();
        }

        private void ParseArgumentList() {
            Emit("ArgumentList");
            Push();
            EmitToken(Consume(SyntaxKind.OpenParenToken, "Expected '('"));
            while (!Check(SyntaxKind.CloseParenToken) && !Check(SyntaxKind.EndOfFileToken)) {
                ParseExpression();
                if (!Match(SyntaxKind.CommaToken)) {
                    break;
                }
            }
            EmitToken(Consume(SyntaxKind.CloseParenToken, "Expected ')'"));
            Pop();
        }

        private void ParseTypeSyntax() {
            Emit("TypeSyntax");
            Push();
            if (IsTypeToken(Current().Kind())) {
                EmitToken(Advance());
            } else {
                EmitToken(Consume(SyntaxKind.IdentifierToken, "Expected type name"));
            }
            ParseOptionalTypeParameters();
            while (Check(SyntaxKind.StarToken)) {
                EmitToken(Advance());
            }
            while (Check(SyntaxKind.OpenBracketToken)) {
                EmitToken(Advance());
                EmitToken(Consume(SyntaxKind.CloseBracketToken, "Expected ']' in array type"));
            }
            Pop();
        }

        private void ParseStackAllocTypeSyntax() {
            Emit("TypeSyntax");
            Push();
            if (IsTypeToken(Current().Kind())) {
                EmitToken(Advance());
            } else {
                EmitToken(Consume(SyntaxKind.IdentifierToken, "Expected type name"));
            }
            ParseOptionalTypeParameters();
            while (Check(SyntaxKind.StarToken)) {
                EmitToken(Advance());
            }
            Pop();
        }

        private void ParseOptionalTypeParameters() {
            if (!Check(SyntaxKind.LessToken)) {
                return;
            }
            Emit("TypeArgumentOrParameterList");
            Push();
            EmitToken(Advance());
            while (!Check(SyntaxKind.GreaterToken) && !Check(SyntaxKind.EndOfFileToken)) {
                if (Current().Kind() == SyntaxKind.IdentifierToken || IsTypeToken(Current().Kind())) {
                    EmitToken(Advance());
                } else if (Check(SyntaxKind.CommaToken)) {
                    EmitToken(Advance());
                } else {
                    diagnostics.Report(Current().Line(), Current().Column(), "Expected type argument or parameter");
                    EmitToken(Advance());
                }
            }
            EmitToken(Consume(SyntaxKind.GreaterToken, "Expected '>'"));
            Pop();
        }

        private void ParseQualifiedName() {
            Emit("QualifiedName");
            Push();
            EmitToken(Consume(SyntaxKind.IdentifierToken, "Expected identifier"));
            while (Match(SyntaxKind.DotToken)) {
                EmitToken(Consume(SyntaxKind.IdentifierToken, "Expected identifier after '.'"));
            }
            Pop();
        }

        private void SkipModifiers() {
            while (SyntaxFacts.IsModifier(Current().Kind())) {
                Emit("Modifier " + SyntaxFacts.KindName(Current().Kind()));
                EmitToken(Advance());
            }
        }

        private bool LooksLikeLocalDeclaration() {
            if (Current().Kind() == SyntaxKind.VarKeyword) {
                return true;
            }
            if (Current().Kind() == SyntaxKind.IdentifierToken) {
                return Peek(1).Kind() == SyntaxKind.IdentifierToken;
            }
            if (!IsTypeToken(Current().Kind())) {
                return false;
            }
            return Peek(1).Kind() == SyntaxKind.IdentifierToken ||
                   Peek(1).Kind() == SyntaxKind.StarToken ||
                   Peek(1).Kind() == SyntaxKind.OpenBracketToken;
        }

        private bool IsTypeToken(SyntaxKind kind) {
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

        private int UnaryPrecedence(SyntaxKind kind) {
            if (kind == SyntaxKind.PlusToken || kind == SyntaxKind.MinusToken || kind == SyntaxKind.BangToken ||
                kind == SyntaxKind.AmpersandToken || kind == SyntaxKind.StarToken) {
                return 7;
            }
            return 0;
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

        private bool Match(SyntaxKind kind) {
            if (!Check(kind)) {
                return false;
            }
            EmitToken(Advance());
            return true;
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

        private void EmitToken(SyntaxToken token) {
            Emit("Token " + SyntaxFacts.KindName(token.Kind()) + " " + token.Text());
        }

        private void Emit(string text) {
            int i = 0;
            while (i < indent) {
                output = output + "  ";
                i = i + 1;
            }
            output = output + text + "\n";
        }

        private void Push() {
            indent = indent + 1;
        }

        private void Pop() {
            indent = indent - 1;
        }
    }
}
