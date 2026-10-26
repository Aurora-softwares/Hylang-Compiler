using Hydrogen.Compiler.Core;

namespace Hydrogen.Compiler.Core {
    public class HyprojManifest {
        private int format;
        private string type;
        private string version;
        private string packageId;
        private string output;
        private string[] sources;
        private string[] projectReferences;
        private string[] dependencyIds;
        private string[] dependencyVersions;
        private bool validDependencies;

        public HyprojManifest(int inputFormat, string inputType, string inputVersion, string inputPackageId, string inputOutput, string[] inputSources, string[] inputProjectReferences, string[] inputDependencyIds, string[] inputDependencyVersions, bool inputValidDependencies) {
            format = inputFormat;
            type = inputType;
            version = inputVersion;
            packageId = inputPackageId;
            output = inputOutput;
            sources = inputSources;
            projectReferences = inputProjectReferences;
            dependencyIds = inputDependencyIds;
            dependencyVersions = inputDependencyVersions;
            validDependencies = inputValidDependencies;
        }

        public int Format() { return format; }
        public string Type() { return type; }
        public string Version() { return version; }
        public string PackageId() { return packageId; }
        public string Output() { return output; }
        public string[] Sources() { return sources; }
        public string[] ProjectReferences() { return projectReferences; }
        public string[] DependencyIds() { return dependencyIds; }
        public string[] DependencyVersions() { return dependencyVersions; }
        public bool ValidDependencies() { return validDependencies; }

        public static HyprojManifest Load(string path) {
            return Parse(System.IO.File.ReadAllText(path));
        }

        public static HyprojManifest Parse(string text) {
            int format = 0;
            string type = "";
            string version = "";
            string packageId = "";
            string output = "";
            string[] sources = new string[0];
            string[] projectReferences = new string[0];
            string[] dependencyIds = new string[0];
            string[] dependencyVersions = new string[0];
            bool validDependencies = true;
            string section = "";

            string[] lines = SplitLines(text);
            int i = 0;
            while (i < lines.Length) {
                string line = Trim(lines[i]);
                if (line == "" || StartsWith(line, "#") || StartsWith(line, "//")) {
                    i = i + 1;
                    continue;
                }
                if (StartsWith(line, "[")) {
                    section = line;
                    i = i + 1;
                    continue;
                }
                int eq = IndexOf(line, "=");
                if (eq < 0) {
                    i = i + 1;
                    continue;
                }
                string key = Trim(Slice(line, 0, eq));
                string value = Trim(Slice(line, eq + 1, line.Length - (eq + 1)));
                while (!ValueComplete(value) && i + 1 < lines.Length) {
                    i = i + 1;
                    value = value + "\n" + Trim(lines[i]);
                }
                if (section == "[package]") {
                    if (key == "id") { packageId = Unquote(value); }
                } else if (section == "[dependencies]") {
                    string version = Unquote(value);
                    if (!ValidPackagePart(key) || !ValidPackagePart(version) ||
                        value.Length < 2 || value[0] != "\"" ||
                        value[value.Length - 1] != "\"" || Contains(dependencyIds, key)) {
                        validDependencies = false;
                    } else {
                        dependencyIds = Append(dependencyIds, dependencyIds.Length, key);
                        dependencyVersions = Append(dependencyVersions, dependencyVersions.Length, version);
                    }
                } else if (section != "") {
                    // Package metadata and future sections do not change root fields.
                } else if (key == "format") {
                    format = ParseInt(value);
                } else if (key == "type") {
                    type = Unquote(value);
                } else if (key == "version") {
                    version = Unquote(value);
                } else if (key == "output") {
                    output = Unquote(value);
                } else if (key == "sources") {
                    sources = ParseStringArray(value);
                } else if (key == "project_references") {
                    projectReferences = ParseStringArray(value);
                }
                i = i + 1;
            }

            return new HyprojManifest(format, type, version, packageId, output, sources, projectReferences,
                dependencyIds, dependencyVersions, validDependencies);
        }

        private static bool Contains(string[] values, string needle) {
            int i = 0;
            while (i < values.Length) {
                if (values[i] == needle) { return true; }
                i = i + 1;
            }
            return false;
        }

        public static bool ValidPackagePart(string value) {
            if (value.Length == 0 || value == "." || value == "..") { return false; }
            if (IndexOf("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", value[0]) < 0) { return false; }
            int i = 0;
            while (i < value.Length) {
                string ch = value[i];
                if (IndexOf("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-", ch) < 0) { return false; }
                i = i + 1;
            }
            return true;
        }

        private static string[] SplitLines(string text) {
            string[] lines = new string[0];
            int count = 0;
            int start = 0;
            int i = 0;
            while (i <= text.Length) {
                if (i == text.Length) {
                    int len = i - start;
                    lines = Append(lines, count, Slice(text, start, len));
                    count = count + 1;
                    start = i + 1;
                } else if (text[i] == "\n") {
                    int len2 = i - start;
                    lines = Append(lines, count, Slice(text, start, len2));
                    count = count + 1;
                    start = i + 1;
                }
                i = i + 1;
            }
            return lines;
        }

        private static bool ValueComplete(string value) {
            int brackets = 0;
            bool quoted = false;
            int i = 0;
            while (i < value.Length) {
                if (value[i] == "\"") { quoted = !quoted; }
                else if (!quoted && value[i] == "[") { brackets = brackets + 1; }
                else if (!quoted && value[i] == "]") { brackets = brackets - 1; }
                i = i + 1;
            }
            return !quoted && brackets <= 0;
        }

        private static string[] ParseStringArray(string raw) {
            // Expect: ["a", "b"]
            string value = Trim(raw);
            if (value.Length < 2) {
                return new string[0];
            }
            if (value[0] != "[" || value[value.Length - 1] != "]") {
                return new string[0];
            }
            string inner = Trim(Slice(value, 1, value.Length - 2));
            string[] items = new string[0];
            int count = 0;
            int i = 0;
            while (i < inner.Length) {
                while (i < inner.Length) {
                    if (!IsSpace(inner[i])) { break; }
                    i = i + 1;
                }
                if (i >= inner.Length) { break; }
                if (inner[i] != "\"") { break; }
                i = i + 1;
                int start = i;
                while (i < inner.Length) {
                    if (inner[i] == "\"") { break; }
                    i = i + 1;
                }
                string item = Slice(inner, start, i - start);
                items = Append(items, count, item);
                count = count + 1;
                if (i < inner.Length) {
                    if (inner[i] == "\"") { i = i + 1; }
                }
                while (i < inner.Length) {
                    if (inner[i] == ",") { break; }
                    i = i + 1;
                }
                if (i < inner.Length) {
                    if (inner[i] == ",") { i = i + 1; }
                }
            }
            return items;
        }

        private static string Unquote(string text) {
            if (text.Length >= 2) {
                if (text[0] == "\"" && text[text.Length - 1] == "\"") {
                    return Slice(text, 1, text.Length - 2);
                }
            }
            return text;
        }

        private static bool StartsWith(string text, string prefix) {
            if (text.Length < prefix.Length) { return false; }
            int i = 0;
            while (i < prefix.Length) {
                if (text[i] != prefix[i]) { return false; }
                i = i + 1;
            }
            return true;
        }

        private static int IndexOf(string text, string needle) {
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
                if (match) { return i; }
                i = i + 1;
            }
            return -1;
        }

        private static string Trim(string text) {
            int start = 0;
            int end = text.Length;
            while (start < end) {
                if (!IsSpace(text[start])) { break; }
                start = start + 1;
            }
            while (end > start) {
                if (!IsSpace(text[end - 1])) { break; }
                end = end - 1;
            }
            return Slice(text, start, end - start);
        }

        private static bool IsSpace(string ch) {
            return ch == " " || ch == "\t" || ch == "\r" || ch == "\n";
        }

        private static int ParseInt(string text) {
            string t = Trim(text);
            int value = 0;
            int i = 0;
            while (i < t.Length) {
                string ch = t[i];
                if (ch == "0") { value = value * 10 + 0; }
                else if (ch == "1") { value = value * 10 + 1; }
                else if (ch == "2") { value = value * 10 + 2; }
                else if (ch == "3") { value = value * 10 + 3; }
                else if (ch == "4") { value = value * 10 + 4; }
                else if (ch == "5") { value = value * 10 + 5; }
                else if (ch == "6") { value = value * 10 + 6; }
                else if (ch == "7") { value = value * 10 + 7; }
                else if (ch == "8") { value = value * 10 + 8; }
                else if (ch == "9") { value = value * 10 + 9; }
                i = i + 1;
            }
            return value;
        }

        private static string Slice(string text, int start, int length) {
            string result = "";
            int i = 0;
            while (i < length && start + i < text.Length) {
                result = result + text[start + i];
                i = i + 1;
            }
            return result;
        }

        private static string[] Append(string[] items, int count, string item) {
            string[] next = new string[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }
    }
}
