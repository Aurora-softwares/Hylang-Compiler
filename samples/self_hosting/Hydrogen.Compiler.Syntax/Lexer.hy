using Hydrogen.Compiler.Diagnostics;
using Hydrogen.Compiler.Text;
using System.Collections;

namespace Hydrogen.Compiler.Syntax {
    public class Lexer {
        private SourceText source;
        private DiagnosticBag diagnostics;
        private int index;
        private int line;
        private int column;

        public Lexer(SourceText inputSource, DiagnosticBag inputDiagnostics) {
            source = inputSource;
            diagnostics = inputDiagnostics;
            index = 0;
            line = 1;
            column = 1;
        }

        public List<SyntaxToken> LexAll() {
            List<SyntaxToken> tokens = new List<SyntaxToken>();
            while (true) {
                SyntaxToken token = NextToken();
                tokens.Add(token);
                if (token.Kind() == SyntaxKind.EndOfFileToken) {
                    return tokens;
                }
            }
            return tokens;
        }

        public SyntaxToken NextToken() {
            SkipWhitespaceAndComments();

            int start = index;
            int startLine = line;
            int startColumn = column;
            if (IsAtEnd()) {
                return new SyntaxToken(SyntaxKind.EndOfFileToken, "<eof>", startLine, startColumn, start);
            }

            string current = Advance();
            if (IsIdentifierStart(current)) {
                return LexIdentifier(start, startLine, startColumn, current);
            }
            if (IsDigit(current)) {
                return LexNumber(start, startLine, startColumn, current);
            }
            if (current == "\"") {
                return LexString(start, startLine, startColumn);
            }

            if (current == "(") { return Token(SyntaxKind.OpenParenToken, current, startLine, startColumn, start); }
            if (current == ")") { return Token(SyntaxKind.CloseParenToken, current, startLine, startColumn, start); }
            if (current == "{") { return Token(SyntaxKind.OpenBraceToken, current, startLine, startColumn, start); }
            if (current == "}") { return Token(SyntaxKind.CloseBraceToken, current, startLine, startColumn, start); }
            if (current == "[") { return Token(SyntaxKind.OpenBracketToken, current, startLine, startColumn, start); }
            if (current == "]") { return Token(SyntaxKind.CloseBracketToken, current, startLine, startColumn, start); }
            if (current == ";") { return Token(SyntaxKind.SemicolonToken, current, startLine, startColumn, start); }
            if (current == ",") { return Token(SyntaxKind.CommaToken, current, startLine, startColumn, start); }
            if (current == ".") { return Token(SyntaxKind.DotToken, current, startLine, startColumn, start); }
            if (current == ":") { return Token(SyntaxKind.ColonToken, current, startLine, startColumn, start); }
            if (current == "+") { return Token(SyntaxKind.PlusToken, current, startLine, startColumn, start); }
            if (current == "-") { return Token(SyntaxKind.MinusToken, current, startLine, startColumn, start); }
            if (current == "*") { return Token(SyntaxKind.StarToken, current, startLine, startColumn, start); }
            if (current == "/") { return Token(SyntaxKind.SlashToken, current, startLine, startColumn, start); }
            if (current == "%") { return Token(SyntaxKind.PercentToken, current, startLine, startColumn, start); }
            if (current == "!") {
                if (Match("=")) { return Token(SyntaxKind.BangEqualsToken, "!=", startLine, startColumn, start); }
                return Token(SyntaxKind.BangToken, current, startLine, startColumn, start);
            }
            if (current == "=") {
                if (Match("=")) { return Token(SyntaxKind.EqualsEqualsToken, "==", startLine, startColumn, start); }
                return Token(SyntaxKind.EqualsToken, current, startLine, startColumn, start);
            }
            if (current == "<") {
                if (Match("=")) { return Token(SyntaxKind.LessEqualsToken, "<=", startLine, startColumn, start); }
                return Token(SyntaxKind.LessToken, current, startLine, startColumn, start);
            }
            if (current == ">") {
                if (Match("=")) { return Token(SyntaxKind.GreaterEqualsToken, ">=", startLine, startColumn, start); }
                return Token(SyntaxKind.GreaterToken, current, startLine, startColumn, start);
            }
            if (current == "&") {
                if (Match("&")) { return Token(SyntaxKind.AmpersandAmpersandToken, "&&", startLine, startColumn, start); }
                return Token(SyntaxKind.AmpersandToken, current, startLine, startColumn, start);
            }
            if (current == "|") {
                if (Match("|")) { return Token(SyntaxKind.PipePipeToken, "||", startLine, startColumn, start); }
            }

            diagnostics.Report(startLine, startColumn, "Unexpected character '" + current + "'");
            return Token(SyntaxKind.BadToken, current, startLine, startColumn, start);
        }

        private SyntaxToken Token(SyntaxKind kind, string text, int tokenLine, int tokenColumn, int position) {
            return new SyntaxToken(kind, text, tokenLine, tokenColumn, position);
        }

        private SyntaxToken LexIdentifier(int start, int startLine, int startColumn, string first) {
            string text = first;
            while (!IsAtEnd() && IsIdentifierPart(Peek())) {
                text = text + Advance();
            }
            return Token(SyntaxFacts.KeywordKind(text), text, startLine, startColumn, start);
        }

        private SyntaxToken LexNumber(int start, int startLine, int startColumn, string first) {
            string text = first;
            if (first == "0" && (Peek() == "x" || Peek() == "X")) {
                text = text + Advance();
                while (!IsAtEnd() && IsHexDigit(Peek())) {
                    text = text + Advance();
                }
                return Token(SyntaxKind.NumberToken, text, startLine, startColumn, start);
            }
            while (!IsAtEnd() && IsDigit(Peek())) {
                text = text + Advance();
            }
            return Token(SyntaxKind.NumberToken, text, startLine, startColumn, start);
        }

        private SyntaxToken LexString(int start, int startLine, int startColumn) {
            string text = "\"";
            while (!IsAtEnd() && Peek() != "\"") {
                string current = Advance();
                text = text + current;
                if (current == "\\" && !IsAtEnd()) {
                    text = text + Advance();
                }
            }
            if (IsAtEnd()) {
                diagnostics.Report(startLine, startColumn, "Unterminated string literal");
                return Token(SyntaxKind.StringToken, text, startLine, startColumn, start);
            }
            text = text + Advance();
            return Token(SyntaxKind.StringToken, text, startLine, startColumn, start);
        }

        private void SkipWhitespaceAndComments() {
            while (!IsAtEnd()) {
                string current = Peek();
                if (current == " " || current == "\t" || current == "\r" || current == "\n") {
                    Advance();
                    continue;
                }
                if (current == "/" && PeekNext() == "/") {
                    while (!IsAtEnd() && Peek() != "\n") {
                        Advance();
                    }
                    continue;
                }
                return;
            }
        }

        private bool Match(string expected) {
            if (Peek() != expected) {
                return false;
            }
            Advance();
            return true;
        }

        private string Peek() {
            return source.CharAt(index);
        }

        private string PeekNext() {
            return source.CharAt(index + 1);
        }

        private string Advance() {
            string result = source.CharAt(index);
            index = index + 1;
            if (result == "\n") {
                line = line + 1;
                column = 1;
            } else {
                column = column + 1;
            }
            return result;
        }

        private bool IsAtEnd() {
            return source.IsAtEnd(index);
        }

        private bool IsIdentifierStart(string text) {
            return text == "_" || IsLetter(text);
        }

        private bool IsIdentifierPart(string text) {
            return IsIdentifierStart(text) || IsDigit(text);
        }

        private bool IsLetter(string text) {
            return text == "a" || text == "b" || text == "c" || text == "d" || text == "e" ||
                   text == "f" || text == "g" || text == "h" || text == "i" || text == "j" ||
                   text == "k" || text == "l" || text == "m" || text == "n" || text == "o" ||
                   text == "p" || text == "q" || text == "r" || text == "s" || text == "t" ||
                   text == "u" || text == "v" || text == "w" || text == "x" || text == "y" ||
                   text == "z" || text == "A" || text == "B" || text == "C" || text == "D" ||
                   text == "E" || text == "F" || text == "G" || text == "H" || text == "I" ||
                   text == "J" || text == "K" || text == "L" || text == "M" || text == "N" ||
                   text == "O" || text == "P" || text == "Q" || text == "R" || text == "S" ||
                   text == "T" || text == "U" || text == "V" || text == "W" || text == "X" ||
                   text == "Y" || text == "Z";
        }

        private bool IsDigit(string text) {
            return text == "0" || text == "1" || text == "2" || text == "3" || text == "4" ||
                   text == "5" || text == "6" || text == "7" || text == "8" || text == "9";
        }

        private bool IsHexDigit(string text) {
            return IsDigit(text) || text == "a" || text == "b" || text == "c" || text == "d" ||
                   text == "e" || text == "f" || text == "A" || text == "B" || text == "C" ||
                   text == "D" || text == "E" || text == "F";
        }
    }
}
