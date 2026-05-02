using Hydrogen.Compiler.Diagnostics;
using Hydrogen.Compiler.Text;

namespace Hydrogen.Compiler.Binding {
    public class SelfHostSubsetValidator {
        public bool Validate(SourceText source, DiagnosticBag diagnostics) {
            string text = source.Content();

            if (Contains(text, "interface")) {
                ReportFirst(source, diagnostics, "interface", "not supported in self-host subset: interface");
            }
            if (Contains(text, "virtual")) {
                ReportFirst(source, diagnostics, "virtual", "not supported in self-host subset: virtual");
            }
            if (Contains(text, "override")) {
                ReportFirst(source, diagnostics, "override", "not supported in self-host subset: override");
            }
            if (Contains(text, "unsafe")) {
                ReportFirst(source, diagnostics, "unsafe", "not supported in self-host subset: unsafe");
            }
            if (Contains(text, "stackalloc")) {
                ReportFirst(source, diagnostics, "stackalloc", "not supported in self-host subset: stackalloc");
            }
            if (Contains(text, "sizeof")) {
                ReportFirst(source, diagnostics, "sizeof", "not supported in self-host subset: sizeof");
            }
            if (Contains(text, "try") || Contains(text, "catch") || Contains(text, "throw")) {
                if (Contains(text, "try")) {
                    ReportFirst(source, diagnostics, "try", "not supported in self-host subset: exceptions");
                } else if (Contains(text, "catch")) {
                    ReportFirst(source, diagnostics, "catch", "not supported in self-host subset: exceptions");
                } else {
                    ReportFirst(source, diagnostics, "throw", "not supported in self-host subset: exceptions");
                }
            }

            // Generics: we keep detection simple and conservative.
            if (Contains(text, "List<") || Contains(text, "Dictionary<") || Contains(text, "HashMap<") || Contains(text, "Map<") || Contains(text, "Set<")) {
                diagnostics.Report(1, 1, "not supported in self-host subset: generics");
            }

            return !diagnostics.HasErrors();
        }

        private bool Contains(string text, string needle) {
            return IndexOf(text, needle) >= 0;
        }

        private void ReportFirst(SourceText source, DiagnosticBag diagnostics, string needle, string message) {
            int index = IndexOf(source.Content(), needle);
            if (index < 0) {
                diagnostics.Report(1, 1, message);
                return;
            }
            TextLocation location = LocationOf(source, index);
            diagnostics.Report(location.Line(), location.Column(), message);
        }

        private TextLocation LocationOf(SourceText source, int index) {
            int line = 1;
            int column = 1;
            int i = 0;
            while (i < index && i < source.Length()) {
                string ch = source.CharAt(i);
                if (ch == "\n") {
                    line = line + 1;
                    column = 1;
                } else {
                    column = column + 1;
                }
                i = i + 1;
            }
            return new TextLocation(line, column);
        }

        private int IndexOf(string text, string needle) {
            int i = 0;
            while (i <= text.Length - needle.Length) {
                int j = 0;
                bool match = true;
                while (j < needle.Length) {
                    if (text[i + j] != needle[j]) {
                        match = false;
                    }
                    j = j + 1;
                }
                if (match) {
                    return i;
                }
                i = i + 1;
            }
            return -1;
        }
    }
}
