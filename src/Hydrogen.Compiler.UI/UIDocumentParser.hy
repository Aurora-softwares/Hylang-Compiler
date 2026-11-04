namespace Hydrogen.Compiler.UI {
    // A bounded lexical preflight. The native host retains authoritative XML
    // schema validation until the full document grammar has been ported.
    public class UIDocumentParser {
        private string source;
        private string error;
        private int elements;
        private int maxDepth;
        private string[] ids;
        private int idCount;

        public UIDocumentParser(string xml) {
            source = xml;
            error = "";
            elements = 0;
            maxDepth = 0;
            ids = new string[513];
            idCount = 0;
        }

        public string Error() { return error; }
        public int Elements() { return elements; }
        public int MaximumDepth() { return maxDepth; }

        public bool Scan() {
            if (source.Length == 0 || source.Length > 1048576) {
                error = "UI document must be between 1 byte and 1 MiB";
                return false;
            }
            ids = new string[513];
            idCount = 0;
            elements = 0;
            maxDepth = 0;
            error = "";
            string[] stack = new string[33];
            int depth = 0;
            int pos = 0;
            bool rootSeen = false;
            while (pos < source.Length) {
                if (source[pos] != "<") { pos = pos + 1; continue; }
                int start = pos + 1;
                if (start >= source.Length) { error = "unterminated markup"; return false; }
                if (source[start] == "?" && !rootSeen) {
                    int declarationEnd = start;
                    while (declarationEnd + 1 < source.Length &&
                           !(source[declarationEnd] == "?" && source[declarationEnd + 1] == ">")) {
                        declarationEnd = declarationEnd + 1;
                    }
                    if (declarationEnd + 1 >= source.Length) { error = "unterminated XML declaration"; return false; }
                    pos = declarationEnd + 2;
                    continue;
                }
                if (source[start] == "!" || source[start] == "?") {
                    // Never resolve external entities, DTDs or arbitrary instructions.
                    error = "DTD, comments and processing instructions are not supported in preflight";
                    return false;
                }
                bool closing = source[start] == "/";
                if (closing) { start = start + 1; }
                int end = start;
                while (end < source.Length && NameCharacter(source[end])) { end = end + 1; }
                if (end == start) { error = "missing element name"; return false; }
                string name = Slice(source, start, end - start);
                if (!KnownElement(name)) { error = "unsupported UI element " + name; return false; }
                int cursor = end;
                bool quoted = false;
                while (cursor < source.Length) {
                    if (source[cursor] == "\"") { quoted = !quoted; }
                    if (source[cursor] == ">" && !quoted) { break; }
                    cursor = cursor + 1;
                }
                if (cursor >= source.Length || quoted) { error = "unterminated element"; return false; }
                int beforeEnd = cursor - 1;
                while (beforeEnd > end && (source[beforeEnd] == " " || source[beforeEnd] == "\\t" || source[beforeEnd] == "\\n")) {
                    beforeEnd = beforeEnd - 1;
                }
                bool selfClosing = beforeEnd >= end && source[beforeEnd] == "/";
                if (closing) {
                    if (selfClosing || !OnlyWhitespace(end, cursor)) {
                        error = "closing elements cannot have attributes";
                        return false;
                    }
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
                    } else if (!AllowedChild(stack[depth - 1], name)) {
                        error = "invalid placement of " + name + " in " + stack[depth - 1];
                        return false;
                    }
                    elements = elements + 1;
                    if (elements > 512 || depth >= 32) {
                        error = "UI nesting or element limit exceeded";
                        return false;
                    }
                    if (!ScanAttributes(name, end, selfClosing ? beforeEnd : cursor)) {
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


        // Keep the self-hosted compiler's preflight aligned with the public
        // HYUI v1 schema, regardless of the target OS or native SDK.
        private static bool Token(string names, string candidate) {
            return Contains("|" + names + "|", "|" + candidate + "|");
        }

        private static bool KnownElement(string name) {
            return Token("Window|ColumnPanel|RowPanel|ScrollView|GridPanel|Panel|MenuBar|Menu|MenuItem|ContextMenu|Popover|Toolbar|ToolButton|Clipboard|Tabs|Tab|ListBox|Table|RadioGroup|Image|Dialog|Label|Button|Input|SearchInput|PasswordInput|FilePicker|TextArea|CheckBox|Switch|Select|Slider|NumberInput|ProgressBar|Spinner|Separator|Spacer|State|Timer", name);
        }

        private static bool Container(string tag) {
            return Token("Window|ColumnPanel|RowPanel|ScrollView|GridPanel|Panel|MenuBar|Menu|ContextMenu|Popover|Toolbar|Tabs|Tab", tag);
        }

        private static bool AllowedChild(string parent, string child) {
            if (!Container(parent)) { return false; }
            if (parent == "Tabs") { return child == "Tab"; }
            if (parent == "MenuBar") { return child == "Menu"; }
            if (parent == "Menu" || parent == "ContextMenu") { return child == "MenuItem"; }
            if (parent == "Toolbar") { return child == "ToolButton"; }
            if (child == "Tab" || child == "Menu" || child == "MenuItem" || child == "ToolButton") { return false; }
            if (Token("MenuBar|Toolbar|ContextMenu|Popover|Clipboard|Dialog", child)) { return parent == "Window"; }
            return true;
        }

        private static bool AllowedAttribute(string tag, string key) {
            if (key == "id") { return true; }
            bool visual = !Token("Window|Timer|State|ContextMenu|Popover|Clipboard", tag);
            if (visual) {
                if (tag == "Toolbar" && Token("visible|enabled", key)) { return true; }
                if (tag == "ToolButton" && Token("visible|enabled|accessibleName|tooltip", key)) { return true; }
                if (tag != "Toolbar" && tag != "ToolButton" && Token("visible|enabled|fill|preferredWidth|accessibleName", key)) { return true; }
                if (tag != "Toolbar" && tag != "ToolButton" && !Token("MenuBar|Menu|MenuItem|Dialog", tag) && key == "tooltip") { return true; }
            }
            if (tag == "Window") { return Token("version|title|width|height|padding|theme|onLoad|material", key); }
            if (tag == "ColumnPanel" || tag == "Tab") { return Token(tag == "Tab" ? "title|gap" : "gap", key); }
            if (tag == "RowPanel") { return Token("gap|breakpoint", key); }
            if (tag == "ScrollView") { return Token("height|gap", key); }
            if (tag == "GridPanel") { return Token("gap|columns|minItemWidth", key); }
            if (tag == "Panel") { return Token("title|padding|gap", key); }
            if (tag == "Menu") { return key == "text"; }
            if (tag == "MenuItem") { return Token("text|onClick|checked|shortcut", key); }
            if (tag == "ContextMenu") { return key == "target"; }
            if (tag == "Popover") { return Token("target|text|open|onClose", key); }
            if (tag == "ToolButton") { return Token("text|onClick", key); }
            if (tag == "Clipboard") { return key == "onRead"; }
            if (tag == "Tabs") { return Token("value|onChange", key); }
            if (tag == "ListBox") { return Token("items|value|height|onChange", key); }
            if (tag == "Table") { return Token("columns|rows|value|height|onChange", key); }
            if (tag == "RadioGroup") { return Token("items|value|onChange", key); }
            if (tag == "Image") { return Token("source|height", key); }
            if (tag == "Dialog") { return Token("title|text|buttons|open|value|onClose", key); }
            if (tag == "Label") { return Token("text|role|tone", key); }
            if (tag == "Button") { return Token("text|onClick|primary", key); }
            if (tag == "Input" || tag == "SearchInput") { return Token("text|placeholder|onChange|onSubmit", key); }
            if (tag == "PasswordInput") { return Token("placeholder|onChange|onSubmit", key); }
            if (tag == "FilePicker") { return Token("mode|text|onPick|onCancel", key); }
            if (tag == "TextArea") { return Token("text|placeholder|onChange|height", key); }
            if (tag == "CheckBox" || tag == "Switch") { return Token("text|checked|onChange", key); }
            if (tag == "Select") { return Token("items|value|onChange", key); }
            if (tag == "Slider" || tag == "NumberInput") { return Token("value|minimum|maximum|onChange", key); }
            if (tag == "ProgressBar") { return Token("value|minimum|maximum|indeterminate", key); }
            if (tag == "Spinner") { return key == "running"; }
            if (tag == "Spacer") { return key == "height"; }
            if (tag == "State") { return key == "value"; }
            if (tag == "Timer") { return Token("interval|running|onTick", key); }
            return false;
        }

        private static bool Space(string ch) {
            return ch == " " || ch == "\t" || ch == "\n" || ch == "\r";
        }
        private bool OnlyWhitespace(int begin, int end) {
            int i = begin;
            while (i < end) {
                if (!Space(source[i])) { return false; }
                i = i + 1;
            }
            return true;
        }

        private static bool Identifier(string value, bool handler) {
            if (value.Length == 0 || value.Length > (handler ? 128 : 64)) { return false; }
            string initial = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_";
            string later = initial + "0123456789" + (handler ? "." : "");
            if (!Contains(initial, value[0])) { return false; }
            int i = 1;
            while (i < value.Length) {
                if (!Contains(later, value[i])) { return false; }
                i = i + 1;
            }
            return true;
        }

        private static bool Number(string value, bool positive, bool timer) {
            if (value.Length == 0) { return false; }
            int number = 0;
            int i = 0;
            while (i < value.Length) {
                if (!Contains("0123456789", value[i])) { return false; }
                number = number * 10 + System.Convert.ToInt32(value[i]);
                if (number > 32767) { return false; }
                i = i + 1;
            }
            if (positive && number == 0) { return false; }
            if (timer && number < 100) { return false; }
            return true;
        }

        private bool ScanAttributes(string tag, int begin, int end) {
            string[] seen = new string[40];
            int seenCount = 0;
            string elementId = "";
            string version = "";
            string mode = "";
            string controlText = "";
            bool hasPick = false;
            bool hasClick = false;
            bool hasTick = false;
            bool hasRead = false;
            bool hasTarget = false;
            int cursor = begin;
            while (cursor < end) {
                while (cursor < end && Space(source[cursor])) { cursor = cursor + 1; }
                if (cursor >= end) { break; }
                int start = cursor;
                while (cursor < end && NameCharacter(source[cursor])) { cursor = cursor + 1; }
                if (start == cursor) { error = "invalid attribute name on " + tag; return false; }
                string key = Slice(source, start, cursor - start);
                while (cursor < end && Space(source[cursor])) { cursor = cursor + 1; }
                if (cursor >= end || source[cursor] != "=") { error = "attribute requires = on " + tag; return false; }
                cursor = cursor + 1;
                while (cursor < end && Space(source[cursor])) { cursor = cursor + 1; }
                if (cursor >= end || (source[cursor] != "\"" && source[cursor] != "'")) {
                    error = "attribute value must be quoted on " + tag;
                    return false;
                }
                string quote = source[cursor];
                cursor = cursor + 1;
                start = cursor;
                while (cursor < end && source[cursor] != quote) {
                    if (source[cursor] == "<") { error = "unescaped < in an attribute"; return false; }
                    cursor = cursor + 1;
                }
                if (cursor >= end) { error = "unterminated attribute value on " + tag; return false; }
                string value = Slice(source, start, cursor - start);
                cursor = cursor + 1;
                if (cursor < end && !Space(source[cursor])) {
                    error = "attributes must be separated by whitespace";
                    return false;
                }
                if (value.Length > 16384 || seenCount >= 40 || !AllowedAttribute(tag, key)) {
                    error = "unsupported or oversized attribute " + key + " on " + tag;
                    return false;
                }
                int i = 0;
                while (i < seenCount) {
                    if (seen[i] == key) { error = "duplicate attribute " + key; return false; }
                    i = i + 1;
                }
                seen[seenCount] = key;
                seenCount = seenCount + 1;
                if (key == "id") { elementId = value; }
                if (key == "version") { version = value; }
                if (key == "mode") { mode = value; }
                if (key == "text") { controlText = value; }
                if (key == "onPick") { hasPick = true; }
                if (key == "onClick") { hasClick = true; }
                if (key == "onTick") { hasTick = true; }
                if (key == "onRead") { hasRead = true; }
                if (key == "target") { hasTarget = value != ""; }
                if (Token("visible|enabled|fill|primary|checked|running|indeterminate|open", key) &&
                    value != "true" && value != "false") {
                    error = key + " must be true or false"; return false;
                }
                bool integer = Token("width|height|padding|gap|breakpoint|columns|minItemWidth|preferredWidth|minimum|maximum|interval", key) && !(key == "columns" && tag == "Table");
                if (key == "value" && tag != "State") { integer = true; }
                if (integer && !Number(value, Token("width|height|columns|minItemWidth", key), key == "interval")) {
                    error = "invalid numeric " + key + " on " + tag; return false;
                }
                if (StartsWith(key, "on") && !Identifier(value, true)) {
                    error = "invalid handler name on " + tag; return false;
                }
                if (key == "theme" && !Token("system|light|dark", value)) { error = "invalid window theme"; return false; }
                if (key == "material" && !Token("auto|glass|solid", value)) { error = "invalid window material"; return false; }
                if (key == "role" && !Token("title|heading|body|caption", value)) { error = "invalid label role"; return false; }
                if (key == "tone" && !Token("normal|muted|accent", value)) { error = "invalid label tone"; return false; }
                if (key == "shortcut" && !Shortcut(value)) { error = "invalid menu shortcut"; return false; }
            }
            if (tag == "Window" && version != "1") { error = "Window requires version=\"1\""; return false; }
            if (tag == "ToolButton" && (controlText == "" || !hasClick)) { error = "ToolButton requires text and onClick"; return false; }
            if (tag == "FilePicker" && (!Token("open|save|folder", mode) || controlText == "" || !hasPick)) {
                error = "FilePicker requires mode, text and onPick"; return false;
            }
            if (tag == "Timer" && !hasTick) { error = "Timer requires onTick"; return false; }
            if (tag == "Clipboard" && (elementId == "" || !hasRead)) { error = "Clipboard requires id and onRead"; return false; }
            if (tag == "ContextMenu" && !hasTarget) { error = "ContextMenu requires target"; return false; }
            if (tag == "Popover" && (elementId == "" || !hasTarget || controlText == "")) {
                error = "Popover requires id, target and text"; return false;
            }
            if (elementId == "") { elementId = "_hyui" + elements; }
            if (!Identifier(elementId, false)) { error = "invalid UI element id"; return false; }
            int j = 0;
            while (j < idCount) {
                if (ids[j] == elementId) { error = "duplicate UI element id " + elementId; return false; }
                j = j + 1;
            }
            ids[idCount] = elementId;
            idCount = idCount + 1;
            return true;
        }

        private static bool Shortcut(string value) {
            if (!StartsWith(value, "Primary+")) { return false; }
            string suffix = Slice(value, 8, value.Length - 8);
            if (StartsWith(suffix, "Shift+")) { suffix = Slice(suffix, 6, suffix.Length - 6); }
            return suffix.Length == 1 && Contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", suffix);
        }

        private static bool StartsWith(string value, string prefix) {
            if (value.Length < prefix.Length) { return false; }
            int i = 0;
            while (i < prefix.Length) {
                if (value[i] != prefix[i]) { return false; }
                i = i + 1;
            }
            return true;
        }

        private static bool Contains(string value, string needle) {
            int i = 0;
            while (i + needle.Length <= value.Length) {
                int j = 0;
                while (j < needle.Length && value[i + j] == needle[j]) { j = j + 1; }
                if (j == needle.Length) { return true; }
                i = i + 1;
            }
            return false;
        }

        private static bool NameCharacter(string c) {
            string valid = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-";
            int i = 0;
            while (i < valid.Length) {
                if (valid[i] == c) { return true; }
                i = i + 1;
            }
            return false;
        }
        private static string Slice(string text, int start, int length) {
            string value = "";
            int i = 0;
            while (i < length) { value = value + text[start + i]; i = i + 1; }
            return value;
        }
    }
}
