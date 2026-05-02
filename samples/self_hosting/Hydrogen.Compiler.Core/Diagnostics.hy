using Hydrogen.Compiler.Text;

namespace Hydrogen.Compiler.Diagnostics {
    public class Diagnostic {
        private TextLocation location;
        private string message;

        public Diagnostic(TextLocation inputLocation, string inputMessage) {
            location = inputLocation;
            message = inputMessage;
        }

        public TextLocation Location() {
            return location;
        }

        public string Message() {
            return message;
        }

        public string ToLine() {
            return location.ToDisplayString() + " error " + message;
        }
    }

    public class DiagnosticBag {
        private Diagnostic[] diagnostics;
        private int count;

        public DiagnosticBag() {
            diagnostics = new Diagnostic[16];
            count = 0;
        }

        public void Report(int line, int column, string message) {
            if (count >= diagnostics.Length) {
                Grow();
            }
            diagnostics[count] = new Diagnostic(new TextLocation(line, column), message);
            count = count + 1;
        }

        public int Count() {
            return count;
        }

        public Diagnostic Get(int index) {
            return diagnostics[index];
        }

        public bool HasErrors() {
            return count != 0;
        }

        public string ToText() {
            string result = "";
            int index = 0;
            while (index < count) {
                result = result + diagnostics[index].ToLine() + "\n";
                index = index + 1;
            }
            return result;
        }

        private void Grow() {
            int newSize = diagnostics.Length * 2;
            Diagnostic[] next = new Diagnostic[newSize];
            int i = 0;
            while (i < diagnostics.Length) {
                next[i] = diagnostics[i];
                i = i + 1;
            }
            diagnostics = next;
        }
    }
}
