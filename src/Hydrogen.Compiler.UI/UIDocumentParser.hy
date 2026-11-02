namespace Hydrogen.Compiler.UI {
    // A bounded lexical preflight. The native host retains authoritative XML
    // schema validation until the full document grammar has been ported.
    public class UIDocumentParser {
        private string source;
        private string error;
        private int elements;
        private int maxDepth;

        public UIDocumentParser(string xml) {
            source = xml;
            error = "";
            elements = 0;
            maxDepth = 0;
        }

        public string Error() { return error; }
        public int Elements() { return elements; }
        public int MaximumDepth() { return maxDepth; }

        public bool Scan() {
            if (source.Length == 0 || source.Length > 1048576) {
                error = "UI document must be between 1 byte and 1 MiB";
                return false;
            }
            string[] stack = new string[33];
            int depth = 0;
            int pos = 0;
            bool rootSeen = false;
            while (pos < source.Length) {
                if (source[pos] != "<") { pos = pos + 1; continue; }
                int start = pos + 1;
                if (start >= source.Length) { error = "unterminated markup"; return false; }
                if (source[start] == "!" || source[start] == "?") {
                    // Reject DTDs and processing instructions: no external entities.
                    error = "XML declarations, DTDs and markup directives are not supported";
                    return false;
                }
                bool closing = source[start] == "/";
                if (closing) { start = start + 1; }
                int end = start;
                while (end < source.Length && NameCharacter(source[end])) { end = end + 1; }
                if (end == start) { error = "missing element name"; return false; }
                string name = Slice(source, start, end - start);
                int cursor = end;
                bool quoted = false;
                while (cursor < source.Length) {
                    if (source[cursor] == "\"") { quoted = !quoted; }
                    if (source[cursor] == ">" && !quoted) { break; }
                    cursor = cursor + 1;
                }
                if (cursor >= source.Length || quoted) { error = "unterminated element"; return false; }
                bool selfClosing = cursor > end && source[cursor - 1] == "/";
                if (closing) {
                    if (depth == 0 || stack[depth - 1] != name) {
                        error = "mismatched closing element " + name;
                        return false;
                    }
                    depth = depth - 1;
                } else {
                    if (!rootSeen) {
                        rootSeen = true;
                        if (name != "Window") { error = "root element must be Window"; return false; }
                    } else if (depth == 0) {
                        error = "multiple root elements";
                        return false;
                    }
                    elements = elements + 1;
                    if (elements > 512 || depth >= 32) {
                        error = "UI nesting or element limit exceeded";
                        return false;
                    }
                    if (!selfClosing) {
                        stack[depth] = name;
                        depth = depth + 1;
                        if (depth > maxDepth) { maxDepth = depth; }
                    }
                }
                pos = cursor + 1;
            }
            if (!rootSeen || depth != 0) { error = "missing or unclosed Window"; return false; }
            return true;
        }

        private static bool NameCharacter(string c) {
            return (c >= "A" && c <= "Z") || (c >= "a" && c <= "z") ||
                (c >= "0" && c <= "9") || c == "_" || c == "-";
        }
        private static string Slice(string text, int start, int length) {
            string value = "";
            int i = 0;
            while (i < length) { value = value + text[start + i]; i = i + 1; }
            return value;
        }
    }
}
