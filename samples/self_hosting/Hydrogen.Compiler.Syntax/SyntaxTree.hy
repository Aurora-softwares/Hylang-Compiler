using Hydrogen.Compiler.Diagnostics;
using Hydrogen.Compiler.Text;
using System.Collections;

namespace Hydrogen.Compiler.Syntax {
    public class SyntaxTree {
        private SourceText source;
        private List<SyntaxToken> tokens;
        private DiagnosticBag diagnostics;
        private string outline;

        public SyntaxTree(SourceText inputSource, List<SyntaxToken> inputTokens, DiagnosticBag inputDiagnostics, string inputOutline) {
            source = inputSource;
            tokens = inputTokens;
            diagnostics = inputDiagnostics;
            outline = inputOutline;
        }

        public static SyntaxTree Parse(SourceText source) {
            DiagnosticBag diagnostics = new DiagnosticBag();
            Lexer lexer = new Lexer(source, diagnostics);
            List<SyntaxToken> tokens = lexer.LexAll();
            Parser parser = new Parser(tokens, diagnostics);
            string outline = parser.ParseCompilationUnit();
            return new SyntaxTree(source, tokens, diagnostics, outline);
        }

        public SourceText Source() {
            return source;
        }

        public List<SyntaxToken> Tokens() {
            return tokens;
        }

        public DiagnosticBag Diagnostics() {
            return diagnostics;
        }

        public string Outline() {
            return outline;
        }

        public string TokensText() {
            string result = "";
            int index = 0;
            while (index < tokens.Count()) {
                result = result + tokens.Get(index).ToLine() + "\n";
                index = index + 1;
            }
            if (diagnostics.HasErrors()) {
                result = result + diagnostics.ToText();
            }
            return result;
        }

        public string ParseText() {
            if (diagnostics.HasErrors()) {
                return outline + diagnostics.ToText();
            }
            return outline;
        }
    }
}
