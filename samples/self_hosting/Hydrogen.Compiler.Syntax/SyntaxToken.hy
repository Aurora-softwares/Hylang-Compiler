using Hydrogen.Compiler.Text;

namespace Hydrogen.Compiler.Syntax {
    public class SyntaxToken {
        private SyntaxKind kind;
        private string text;
        private int line;
        private int column;
        private int position;

        public SyntaxToken(SyntaxKind inputKind, string inputText, int inputLine, int inputColumn, int inputPosition) {
            kind = inputKind;
            text = inputText;
            line = inputLine;
            column = inputColumn;
            position = inputPosition;
        }

        public SyntaxKind Kind() {
            return kind;
        }

        public string Text() {
            return text;
        }

        public int Line() {
            return line;
        }

        public int Column() {
            return column;
        }

        public int Position() {
            return position;
        }

        public TextSpan Span() {
            return new TextSpan(position, text.Length);
        }

        public string ToLine() {
            return line + ":" + column + " " + SyntaxFacts.KindName(kind) + " " + text;
        }
    }
}
