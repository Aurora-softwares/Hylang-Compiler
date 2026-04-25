namespace Hydrogen.Compiler.Text {
    public struct TextSpan {
        private int start;
        private int length;

        public TextSpan(int inputStart, int inputLength) {
            start = inputStart;
            length = inputLength;
        }

        public int Start() {
            return start;
        }

        public int Length() {
            return length;
        }

        public int End() {
            return start + length;
        }

        public string ToDisplayString() {
            return start + ":" + length;
        }
    }

    public struct TextLocation {
        private int line;
        private int column;

        public TextLocation(int inputLine, int inputColumn) {
            line = inputLine;
            column = inputColumn;
        }

        public int Line() {
            return line;
        }

        public int Column() {
            return column;
        }

        public string ToDisplayString() {
            return line + ":" + column;
        }
    }

    public class SourceText {
        private string content;

        public SourceText(string input) {
            content = input;
        }

        public static SourceText FromFile(string path) {
            return new SourceText(System.IO.File.ReadAllText(path));
        }

        public string Content() {
            return content;
        }

        public int Length() {
            return content.Length;
        }

        public bool IsAtEnd(int index) {
            return index >= content.Length;
        }

        public string CharAt(int index) {
            if (index < 0 || index >= content.Length) {
                return "";
            }
            return content[index];
        }

        public string Slice(int start, int length) {
            string result = "";
            int index = 0;
            while (index < length && start + index < content.Length) {
                result = result + content[start + index];
                index = index + 1;
            }
            return result;
        }
    }
}
