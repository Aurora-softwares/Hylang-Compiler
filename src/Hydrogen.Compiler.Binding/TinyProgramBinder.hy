using Hydrogen.Compiler.Diagnostics;
using Hydrogen.Compiler.IR;
using Hydrogen.Compiler.Syntax;
using Hydrogen.Compiler.Text;

namespace Hydrogen.Compiler.Binding {
    public class BindResult {
        private bool success;
        private DiagnosticBag diagnostics;
        private IrProgram program;

        public BindResult(bool inputSuccess, DiagnosticBag inputDiagnostics, IrProgram inputProgram) {
            success = inputSuccess;
            diagnostics = inputDiagnostics;
            program = inputProgram;
        }

        public bool Success() {
            return success;
        }

        public DiagnosticBag Diagnostics() {
            return diagnostics;
        }

        public IrProgram Program() {
            return program;
        }
    }

    public class TinyProgramBinder {
        public BindResult Bind(SyntaxTree tree) {
            DiagnosticBag diagnostics = new DiagnosticBag();
            if (tree.Diagnostics().HasErrors()) {
                CopyDiagnostics(tree.Diagnostics(), diagnostics);
            }

            SourceText source = tree.Source();
            string text = source.Content();
            int writeLine = FindPattern(text, "System.Console.WriteLine(\"");
            if (writeLine < 0) {
                diagnostics.Report(1, 1, "Phase 6 native compiler currently supports one System.Console.WriteLine string literal program");
                return new BindResult(false, diagnostics, new IrProgram("", 0));
            }

            string message = ExtractWriteLines(source, diagnostics);
            int exitCode = ExtractExitCode(text, diagnostics);
            return new BindResult(!diagnostics.HasErrors(), diagnostics, new IrProgram(message, exitCode));
        }

        private void CopyDiagnostics(DiagnosticBag source, DiagnosticBag destination) {
            int index = 0;
            while (index < source.Count()) {
                Diagnostic diagnostic = source.Get(index);
                destination.Report(diagnostic.Location().Line(), diagnostic.Location().Column(), diagnostic.Message());
                index = index + 1;
            }
        }

        private int FindPattern(string text, string pattern) {
            int index = 0;
            while (index <= text.Length - pattern.Length) {
                int offset = 0;
                bool match = true;
                while (offset < pattern.Length) {
                    if (text[index + offset] != pattern[offset]) {
                        match = false;
                    }
                    offset = offset + 1;
                }
                if (match) {
                    return index;
                }
                index = index + 1;
            }
            return -1;
        }

        private int FindQuote(string text, int start) {
            int index = start;
            while (index < text.Length) {
                if (text[index] == "\"") {
                    return index;
                }
                index = index + 1;
            }
            return -1;
        }

        private string ExtractWriteLines(SourceText source, DiagnosticBag diagnostics) {
            string text = source.Content();
            string pattern = "System.Console.WriteLine(\"";
            string result = "";
            int searchStart = 0;
            bool first = true;
            while (searchStart < text.Length) {
                int relative = FindPatternFrom(text, pattern, searchStart);
                if (relative < 0) {
                    searchStart = text.Length;
                } else {
                    int start = relative + pattern.Length;
                    int end = FindQuote(text, start);
                    if (end < 0) {
                        diagnostics.Report(1, 1, "unterminated WriteLine string literal");
                        return result;
                    }
                    if (!first) {
                        result = result + "\n";
                    }
                    result = result + source.Slice(start, end - start);
                    first = false;
                    searchStart = end + 1;
                }
            }
            return result;
        }

        private int ExtractExitCode(string text, DiagnosticBag diagnostics) {
            int returnIndex = FindPattern(text, "return ");
            if (returnIndex < 0) {
                return 0;
            }

            int index = returnIndex + "return ".Length;
            int value = 0;
            bool sawDigit = false;
            while (index < text.Length && IsDigit(text[index])) {
                value = value * 10 + DigitValue(text[index]);
                sawDigit = true;
                index = index + 1;
            }

            if (!sawDigit) {
                diagnostics.Report(1, 1, "Phase 6 native compiler currently supports return with an integer literal only");
                return 0;
            }
            return value;
        }

        private int FindPatternFrom(string text, string pattern, int start) {
            int index = start;
            while (index <= text.Length - pattern.Length) {
                int offset = 0;
                bool match = true;
                while (offset < pattern.Length) {
                    if (text[index + offset] != pattern[offset]) {
                        match = false;
                    }
                    offset = offset + 1;
                }
                if (match) {
                    return index;
                }
                index = index + 1;
            }
            return -1;
        }

        private int DigitValue(string ch) {
            if (ch == "0") { return 0; }
            if (ch == "1") { return 1; }
            if (ch == "2") { return 2; }
            if (ch == "3") { return 3; }
            if (ch == "4") { return 4; }
            if (ch == "5") { return 5; }
            if (ch == "6") { return 6; }
            if (ch == "7") { return 7; }
            if (ch == "8") { return 8; }
            if (ch == "9") { return 9; }
            return 0;
        }

        private bool IsDigit(string ch) {
            if (ch == "0") { return true; }
            if (ch == "1") { return true; }
            if (ch == "2") { return true; }
            if (ch == "3") { return true; }
            if (ch == "4") { return true; }
            if (ch == "5") { return true; }
            if (ch == "6") { return true; }
            if (ch == "7") { return true; }
            if (ch == "8") { return true; }
            if (ch == "9") { return true; }
            return false;
        }
    }
}
