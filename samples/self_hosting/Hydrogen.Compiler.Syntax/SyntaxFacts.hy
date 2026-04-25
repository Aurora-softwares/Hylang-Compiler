namespace Hydrogen.Compiler.Syntax {
    public class SyntaxFacts {
        public static string KindName(SyntaxKind kind) {
            if (kind == SyntaxKind.EndOfFileToken) { return "EndOfFile"; }
            if (kind == SyntaxKind.BadToken) { return "Bad"; }
            if (kind == SyntaxKind.IdentifierToken) { return "Identifier"; }
            if (kind == SyntaxKind.NumberToken) { return "Number"; }
            if (kind == SyntaxKind.StringToken) { return "String"; }
            if (kind == SyntaxKind.OpenParenToken) { return "OpenParen"; }
            if (kind == SyntaxKind.CloseParenToken) { return "CloseParen"; }
            if (kind == SyntaxKind.OpenBraceToken) { return "OpenBrace"; }
            if (kind == SyntaxKind.CloseBraceToken) { return "CloseBrace"; }
            if (kind == SyntaxKind.OpenBracketToken) { return "OpenBracket"; }
            if (kind == SyntaxKind.CloseBracketToken) { return "CloseBracket"; }
            if (kind == SyntaxKind.SemicolonToken) { return "Semicolon"; }
            if (kind == SyntaxKind.CommaToken) { return "Comma"; }
            if (kind == SyntaxKind.DotToken) { return "Dot"; }
            if (kind == SyntaxKind.ColonToken) { return "Colon"; }
            if (kind == SyntaxKind.PlusToken) { return "Plus"; }
            if (kind == SyntaxKind.MinusToken) { return "Minus"; }
            if (kind == SyntaxKind.StarToken) { return "Star"; }
            if (kind == SyntaxKind.SlashToken) { return "Slash"; }
            if (kind == SyntaxKind.PercentToken) { return "Percent"; }
            if (kind == SyntaxKind.BangToken) { return "Bang"; }
            if (kind == SyntaxKind.EqualsToken) { return "Equals"; }
            if (kind == SyntaxKind.EqualsEqualsToken) { return "EqualsEquals"; }
            if (kind == SyntaxKind.BangEqualsToken) { return "BangEquals"; }
            if (kind == SyntaxKind.LessToken) { return "Less"; }
            if (kind == SyntaxKind.LessEqualsToken) { return "LessEquals"; }
            if (kind == SyntaxKind.GreaterToken) { return "Greater"; }
            if (kind == SyntaxKind.GreaterEqualsToken) { return "GreaterEquals"; }
            if (kind == SyntaxKind.AmpersandToken) { return "Ampersand"; }
            if (kind == SyntaxKind.AmpersandAmpersandToken) { return "AmpersandAmpersand"; }
            if (kind == SyntaxKind.PipePipeToken) { return "PipePipe"; }
            if (kind == SyntaxKind.UsingKeyword) { return "Using"; }
            if (kind == SyntaxKind.NamespaceKeyword) { return "Namespace"; }
            if (kind == SyntaxKind.ClassKeyword) { return "Class"; }
            if (kind == SyntaxKind.StructKeyword) { return "Struct"; }
            if (kind == SyntaxKind.InterfaceKeyword) { return "Interface"; }
            if (kind == SyntaxKind.EnumKeyword) { return "Enum"; }
            if (kind == SyntaxKind.PublicKeyword) { return "Public"; }
            if (kind == SyntaxKind.PrivateKeyword) { return "Private"; }
            if (kind == SyntaxKind.ProtectedKeyword) { return "Protected"; }
            if (kind == SyntaxKind.InternalKeyword) { return "Internal"; }
            if (kind == SyntaxKind.StaticKeyword) { return "Static"; }
            if (kind == SyntaxKind.VirtualKeyword) { return "Virtual"; }
            if (kind == SyntaxKind.OverrideKeyword) { return "Override"; }
            if (kind == SyntaxKind.VoidKeyword) { return "Void"; }
            if (kind == SyntaxKind.BoolKeyword) { return "Bool"; }
            if (kind == SyntaxKind.ByteKeyword) { return "Byte"; }
            if (kind == SyntaxKind.SByteKeyword) { return "SByte"; }
            if (kind == SyntaxKind.ShortKeyword) { return "Short"; }
            if (kind == SyntaxKind.UShortKeyword) { return "UShort"; }
            if (kind == SyntaxKind.IntKeyword) { return "Int"; }
            if (kind == SyntaxKind.UIntKeyword) { return "UInt"; }
            if (kind == SyntaxKind.LongKeyword) { return "Long"; }
            if (kind == SyntaxKind.ULongKeyword) { return "ULong"; }
            if (kind == SyntaxKind.NIntKeyword) { return "NInt"; }
            if (kind == SyntaxKind.NUIntKeyword) { return "NUInt"; }
            if (kind == SyntaxKind.StringKeyword) { return "StringKeyword"; }
            if (kind == SyntaxKind.VarKeyword) { return "Var"; }
            if (kind == SyntaxKind.TrueKeyword) { return "True"; }
            if (kind == SyntaxKind.FalseKeyword) { return "False"; }
            if (kind == SyntaxKind.NullKeyword) { return "Null"; }
            if (kind == SyntaxKind.IfKeyword) { return "If"; }
            if (kind == SyntaxKind.ElseKeyword) { return "Else"; }
            if (kind == SyntaxKind.WhileKeyword) { return "While"; }
            if (kind == SyntaxKind.ForKeyword) { return "For"; }
            if (kind == SyntaxKind.BreakKeyword) { return "Break"; }
            if (kind == SyntaxKind.ContinueKeyword) { return "Continue"; }
            if (kind == SyntaxKind.ReturnKeyword) { return "Return"; }
            if (kind == SyntaxKind.NewKeyword) { return "New"; }
            if (kind == SyntaxKind.ThisKeyword) { return "This"; }
            if (kind == SyntaxKind.BaseKeyword) { return "Base"; }
            if (kind == SyntaxKind.UnsafeKeyword) { return "Unsafe"; }
            if (kind == SyntaxKind.SizeOfKeyword) { return "SizeOf"; }
            if (kind == SyntaxKind.StackAllocKeyword) { return "StackAlloc"; }
            return "Unknown";
        }

        public static SyntaxKind KeywordKind(string text) {
            if (text == "using") { return SyntaxKind.UsingKeyword; }
            if (text == "namespace") { return SyntaxKind.NamespaceKeyword; }
            if (text == "class") { return SyntaxKind.ClassKeyword; }
            if (text == "struct") { return SyntaxKind.StructKeyword; }
            if (text == "interface") { return SyntaxKind.InterfaceKeyword; }
            if (text == "enum") { return SyntaxKind.EnumKeyword; }
            if (text == "public") { return SyntaxKind.PublicKeyword; }
            if (text == "private") { return SyntaxKind.PrivateKeyword; }
            if (text == "protected") { return SyntaxKind.ProtectedKeyword; }
            if (text == "internal") { return SyntaxKind.InternalKeyword; }
            if (text == "static") { return SyntaxKind.StaticKeyword; }
            if (text == "virtual") { return SyntaxKind.VirtualKeyword; }
            if (text == "override") { return SyntaxKind.OverrideKeyword; }
            if (text == "void") { return SyntaxKind.VoidKeyword; }
            if (text == "bool") { return SyntaxKind.BoolKeyword; }
            if (text == "byte") { return SyntaxKind.ByteKeyword; }
            if (text == "sbyte") { return SyntaxKind.SByteKeyword; }
            if (text == "short") { return SyntaxKind.ShortKeyword; }
            if (text == "ushort") { return SyntaxKind.UShortKeyword; }
            if (text == "int") { return SyntaxKind.IntKeyword; }
            if (text == "uint") { return SyntaxKind.UIntKeyword; }
            if (text == "long") { return SyntaxKind.LongKeyword; }
            if (text == "ulong") { return SyntaxKind.ULongKeyword; }
            if (text == "nint") { return SyntaxKind.NIntKeyword; }
            if (text == "nuint") { return SyntaxKind.NUIntKeyword; }
            if (text == "string") { return SyntaxKind.StringKeyword; }
            if (text == "var") { return SyntaxKind.VarKeyword; }
            if (text == "true") { return SyntaxKind.TrueKeyword; }
            if (text == "false") { return SyntaxKind.FalseKeyword; }
            if (text == "null") { return SyntaxKind.NullKeyword; }
            if (text == "if") { return SyntaxKind.IfKeyword; }
            if (text == "else") { return SyntaxKind.ElseKeyword; }
            if (text == "while") { return SyntaxKind.WhileKeyword; }
            if (text == "for") { return SyntaxKind.ForKeyword; }
            if (text == "break") { return SyntaxKind.BreakKeyword; }
            if (text == "continue") { return SyntaxKind.ContinueKeyword; }
            if (text == "return") { return SyntaxKind.ReturnKeyword; }
            if (text == "new") { return SyntaxKind.NewKeyword; }
            if (text == "this") { return SyntaxKind.ThisKeyword; }
            if (text == "base") { return SyntaxKind.BaseKeyword; }
            if (text == "unsafe") { return SyntaxKind.UnsafeKeyword; }
            if (text == "sizeof") { return SyntaxKind.SizeOfKeyword; }
            if (text == "stackalloc") { return SyntaxKind.StackAllocKeyword; }
            return SyntaxKind.IdentifierToken;
        }

        public static bool IsModifier(SyntaxKind kind) {
            return kind == SyntaxKind.PublicKeyword ||
                   kind == SyntaxKind.PrivateKeyword ||
                   kind == SyntaxKind.ProtectedKeyword ||
                   kind == SyntaxKind.InternalKeyword ||
                   kind == SyntaxKind.StaticKeyword ||
                   kind == SyntaxKind.VirtualKeyword ||
                   kind == SyntaxKind.OverrideKeyword;
        }

        public static bool IsTypeDeclarationStart(SyntaxKind kind) {
            return kind == SyntaxKind.ClassKeyword ||
                   kind == SyntaxKind.StructKeyword ||
                   kind == SyntaxKind.InterfaceKeyword ||
                   kind == SyntaxKind.EnumKeyword;
        }
    }
}
