using Hydrogen.Compiler.Text;

namespace Hydrogen.Compiler.Syntax {
    public class SyntaxNode {
        private string name;
        private TextSpan span;

        public SyntaxNode(string inputName, TextSpan inputSpan) {
            name = inputName;
            span = inputSpan;
        }

        public string Name() {
            return name;
        }

        public TextSpan Span() {
            return span;
        }

        public string ToLine() {
            return name + " " + span.ToDisplayString();
        }
    }
}
