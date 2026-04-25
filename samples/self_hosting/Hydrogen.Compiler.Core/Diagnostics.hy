using Hydrogen.Compiler.Text;
using System.Collections;

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
        private List<Diagnostic> diagnostics;

        public DiagnosticBag() {
            diagnostics = new List<Diagnostic>();
        }

        public void Report(int line, int column, string message) {
            diagnostics.Add(new Diagnostic(new TextLocation(line, column), message));
        }

        public int Count() {
            return diagnostics.Count();
        }

        public Diagnostic Get(int index) {
            return diagnostics.Get(index);
        }

        public bool HasErrors() {
            return diagnostics.Count() != 0;
        }

        public string ToText() {
            string result = "";
            int index = 0;
            while (index < diagnostics.Count()) {
                result = result + diagnostics.Get(index).ToLine() + "\n";
                index = index + 1;
            }
            return result;
        }
    }
}
