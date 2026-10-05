namespace TokenDump {
    public class Scanner {
        private string source;
        private int index;
        private int line;
        private int column;

        public Scanner(string sourceText) {
            source = sourceText;
            index = 0;
            line = 1;
            column = 1;
        }

        public Token NextToken() {
            SkipWhitespaceAndComments();

            int startLine = line;
            int startColumn = column;
            if (IsAtEnd()) {
                return new Token(TokenKind.EndOfFile, "<eof>", startLine, startColumn);
            }

            string current = Advance();
            if (IsIdentifierStart(current)) {
                return ScanIdentifier(startLine, startColumn, current);
            }
            if (IsDigit(current)) {
                return ScanNumber(startLine, startColumn, current);
            }
            if (current == "\"") {
                return ScanString(startLine, startColumn);
            }
            if (current == "(") {
                return new Token(TokenKind.OpenParen, current, startLine, startColumn);
            }
            if (current == ")") {
                return new Token(TokenKind.CloseParen, current, startLine, startColumn);
            }
            if (current == "{") {
                return new Token(TokenKind.OpenBrace, current, startLine, startColumn);
            }
            if (current == "}") {
                return new Token(TokenKind.CloseBrace, current, startLine, startColumn);
            }
            if (current == "[") {
                return new Token(TokenKind.OpenBracket, current, startLine, startColumn);
            }
            if (current == "]") {
                return new Token(TokenKind.CloseBracket, current, startLine, startColumn);
            }
            if (current == ";") {
                return new Token(TokenKind.Semicolon, current, startLine, startColumn);
            }
            if (current == ",") {
                return new Token(TokenKind.Comma, current, startLine, startColumn);
            }
            if (current == ".") {
                return new Token(TokenKind.Dot, current, startLine, startColumn);
            }
            if (current == "+") {
                return new Token(TokenKind.Plus, current, startLine, startColumn);
            }
            if (current == "-") {
                return new Token(TokenKind.Minus, current, startLine, startColumn);
            }
            if (current == "*") {
                return new Token(TokenKind.Star, current, startLine, startColumn);
            }
            if (current == "/") {
                return new Token(TokenKind.Slash, current, startLine, startColumn);
            }
            if (current == "%") {
                return new Token(TokenKind.Percent, current, startLine, startColumn);
            }
            if (current == "!") {
                if (Match("=")) {
                    return new Token(TokenKind.BangEquals, "!=", startLine, startColumn);
                }
                return new Token(TokenKind.Bang, current, startLine, startColumn);
            }
            if (current == "=") {
                if (Match("=")) {
                    return new Token(TokenKind.EqualsEquals, "==", startLine, startColumn);
                }
                return new Token(TokenKind.Equals, current, startLine, startColumn);
            }
            if (current == "<") {
                if (Match("=")) {
                    return new Token(TokenKind.LessEquals, "<=", startLine, startColumn);
                }
                return new Token(TokenKind.Less, current, startLine, startColumn);
            }
            if (current == ">") {
                if (Match("=")) {
                    return new Token(TokenKind.GreaterEquals, ">=", startLine, startColumn);
                }
                return new Token(TokenKind.Greater, current, startLine, startColumn);
            }
            if (current == "&") {
                if (Match("&")) {
                    return new Token(TokenKind.AmpAmp, "&&", startLine, startColumn);
                }
                return new Token(TokenKind.Unknown, current, startLine, startColumn);
            }
            if (current == "|") {
                if (Match("|")) {
                    return new Token(TokenKind.PipePipe, "||", startLine, startColumn);
                }
                return new Token(TokenKind.Unknown, current, startLine, startColumn);
            }

            return new Token(TokenKind.Unknown, current, startLine, startColumn);
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

        private Token ScanIdentifier(int startLine, int startColumn, string first) {
            string text = first;
            while (!IsAtEnd() && IsIdentifierPart(Peek())) {
                text = text + Advance();
            }
            return new Token(KeywordKind(text), text, startLine, startColumn);
        }

        private Token ScanNumber(int startLine, int startColumn, string first) {
            string text = first;
            while (!IsAtEnd() && IsDigit(Peek())) {
                text = text + Advance();
            }
            return new Token(TokenKind.Number, text, startLine, startColumn);
        }

        private Token ScanString(int startLine, int startColumn) {
            string text = "\"";
            while (!IsAtEnd() && Peek() != "\"") {
                string current = Advance();
                text = text + current;
                if (current == "\\") {
                    if (!IsAtEnd()) {
                        text = text + Advance();
                    }
                }
            }
            if (!IsAtEnd()) {
                text = text + Advance();
            }
            return new Token(TokenKind.StringLiteral, text, startLine, startColumn);
        }

        private TokenKind KeywordKind(string text) {
            if (text == "using") {
                return TokenKind.Using;
            }
            if (text == "namespace") {
                return TokenKind.Namespace;
            }
            if (text == "class") {
                return TokenKind.Class;
            }
            if (text == "enum") {
                return TokenKind.Enum;
            }
            if (text == "public") {
                return TokenKind.Public;
            }
            if (text == "private") {
                return TokenKind.Private;
            }
            if (text == "protected") {
                return TokenKind.Protected;
            }
            if (text == "internal") {
                return TokenKind.Internal;
            }
            if (text == "static") {
                return TokenKind.Static;
            }
            if (text == "void") {
                return TokenKind.Void;
            }
            if (text == "int") {
                return TokenKind.Int;
            }
            if (text == "string") {
                return TokenKind.StringKeyword;
            }
            if (text == "bool") {
                return TokenKind.Bool;
            }
            if (text == "true") {
                return TokenKind.True;
            }
            if (text == "false") {
                return TokenKind.False;
            }
            if (text == "null") {
                return TokenKind.Null;
            }
            if (text == "if") {
                return TokenKind.If;
            }
            if (text == "else") {
                return TokenKind.Else;
            }
            if (text == "while") {
                return TokenKind.While;
            }
            if (text == "for") {
                return TokenKind.For;
            }
            if (text == "break") {
                return TokenKind.Break;
            }
            if (text == "continue") {
                return TokenKind.Continue;
            }
            if (text == "return") {
                return TokenKind.Return;
            }
            if (text == "new") {
                return TokenKind.New;
            }
            if (text == "this") {
                return TokenKind.This;
            }
            return TokenKind.Identifier;
        }

        private bool Match(string expected) {
            if (Peek() != expected) {
                return false;
            }
            Advance();
            return true;
        }

        private bool IsAtEnd() {
            return index >= source.Length;
        }

        private string Peek() {
            if (IsAtEnd()) {
                return "";
            }
            return source[index];
        }

        private string PeekNext() {
            if (index + 1 >= source.Length) {
                return "";
            }
            return source[index + 1];
        }

        private string Advance() {
            if (IsAtEnd()) {
                return "";
            }

            string current = source[index];
            index = index + 1;
            if (current == "\n") {
                line = line + 1;
                column = 1;
            } else {
                column = column + 1;
            }
            return current;
        }

        private bool IsIdentifierStart(string value) {
            return IsLetter(value) || value == "_";
        }

        private bool IsIdentifierPart(string value) {
            return IsIdentifierStart(value) || IsDigit(value);
        }

        private bool IsDigit(string value) {
            return value == "0" || value == "1" || value == "2" || value == "3" || value == "4" ||
                   value == "5" || value == "6" || value == "7" || value == "8" || value == "9";
        }

        private bool IsLetter(string value) {
            return value == "a" || value == "b" || value == "c" || value == "d" || value == "e" ||
                   value == "f" || value == "g" || value == "h" || value == "i" || value == "j" ||
                   value == "k" || value == "l" || value == "m" || value == "n" || value == "o" ||
                   value == "p" || value == "q" || value == "r" || value == "s" || value == "t" ||
                   value == "u" || value == "v" || value == "w" || value == "x" || value == "y" ||
                   value == "z" || value == "A" || value == "B" || value == "C" || value == "D" ||
                   value == "E" || value == "F" || value == "G" || value == "H" || value == "I" ||
                   value == "J" || value == "K" || value == "L" || value == "M" || value == "N" ||
                   value == "O" || value == "P" || value == "Q" || value == "R" || value == "S" ||
                   value == "T" || value == "U" || value == "V" || value == "W" || value == "X" ||
                   value == "Y" || value == "Z";
        }
    }
}
