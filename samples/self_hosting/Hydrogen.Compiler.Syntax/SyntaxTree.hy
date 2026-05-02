using Hydrogen.Compiler.Diagnostics;
using Hydrogen.Compiler.Text;

namespace Hydrogen.Compiler.Syntax {
    public class SyntaxTree {
        private SourceText source;
        private SyntaxTokenList tokens;
        private DiagnosticBag diagnostics;
        private string outline;
        private CompilationUnitSyntax root;

        public SyntaxTree(SourceText inputSource, SyntaxTokenList inputTokens, DiagnosticBag inputDiagnostics, string inputOutline, CompilationUnitSyntax inputRoot) {
            source = inputSource;
            tokens = inputTokens;
            diagnostics = inputDiagnostics;
            outline = inputOutline;
            root = inputRoot;
        }

        public static SyntaxTree Parse(SourceText source) {
            DiagnosticBag diagnostics = new DiagnosticBag();
            Lexer lexer = new Lexer(source, diagnostics);
            SyntaxTokenList tokens = lexer.LexAll();
            Parser parser = new Parser(tokens, diagnostics);
            string outline = parser.ParseCompilationUnit();
            AstParser ast = new AstParser(tokens, diagnostics);
            CompilationUnitSyntax root = ast.ParseCompilationUnit();
            return new SyntaxTree(source, tokens, diagnostics, outline, root);
        }

        public static SyntaxTree ParseFast(SourceText source) {
            // Fast path used by the self-hosting compiler pipeline: skip the outline parser.
            DiagnosticBag diagnostics = new DiagnosticBag();
            Lexer lexer = new Lexer(source, diagnostics);
            SyntaxTokenList tokens = lexer.LexAll();
            AstParser ast = new AstParser(tokens, diagnostics);
            CompilationUnitSyntax root = ast.ParseCompilationUnit();
            return new SyntaxTree(source, tokens, diagnostics, "", root);
        }

        public SourceText Source() {
            return source;
        }

        public SyntaxTokenList Tokens() {
            return tokens;
        }

        public DiagnosticBag Diagnostics() {
            return diagnostics;
        }

        public string Outline() {
            return outline;
        }

        public CompilationUnitSyntax Root() {
            return root;
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
