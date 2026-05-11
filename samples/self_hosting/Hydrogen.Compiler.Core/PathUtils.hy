namespace Hydrogen.Compiler.Core {
    public class PathUtils {
        public static string DirName(string path) {
            int i = path.Length - 1;
            while (i >= 0) {
                string ch = path[i];
                if (ch == "/") {
                    if (i == 0) {
                        return "/";
                    }
                    return Slice(path, 0, i);
                }
                i = i - 1;
            }
            return ".";
        }

        public static string Join(string baseDir, string relative) {
            if (relative.Length > 0) {
                if (relative[0] == "/") {
                    return Normalize(relative);
                }
            }
            if (baseDir == ".") {
                return Normalize(relative);
            }
            if (EndsWithSlash(baseDir)) {
                return Normalize(baseDir + relative);
            }
            return Normalize(baseDir + "/" + relative);
        }

        public static string Normalize(string path) {
            // Normalize path by resolving "./" and "../" segments. Very small implementation
            // intended for repo-local deterministic builds.
            string[] parts = Split(path, "/");
            string[] stack = new string[0];
            int count = 0;

            int i = 0;
            while (i < parts.Length) {
                string part = parts[i];
                if (part == "" || part == ".") {
                    // skip
                } else if (part == "..") {
                    if (count > 0) {
                        count = count - 1;
                    } else {
                        // Preserve leading ".." segments in relative paths.
                        stack = Append(stack, count, "..");
                        count = count + 1;
                    }
                } else {
                    stack = Append(stack, count, part);
                    count = count + 1;
                }
                i = i + 1;
            }

            bool rooted = false;
            if (path.Length > 0) {
                rooted = path[0] == "/";
            }
            string result = "";
            if (rooted) {
                result = "/";
            }
            int j = 0;
            while (j < count) {
                if (j > 0 || rooted) {
                    if (!(rooted && j == 0 && result == "/")) {
                        if (result != "") {
                            if (result[result.Length - 1] != "/") {
                                result = result + "/";
                            }
                        }
                    }
                }
                if (rooted && j == 0 && result == "/") {
                    result = result + stack[j];
                } else {
                    if (result == "") {
                        result = stack[j];
                    } else if (result[result.Length - 1] == "/") {
                        result = result + stack[j];
                    } else {
                        result = result + "/" + stack[j];
                    }
                }
                j = j + 1;
            }

            if (result == "") {
                if (rooted) {
                    return "/";
                }
                return ".";
            }
            return result;
        }

        private static bool EndsWithSlash(string text) {
            if (text.Length == 0) {
                return false;
            }
            return text[text.Length - 1] == "/";
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

        private static string[] Split(string text, string separator) {
            // separator must be "/" here; simple splitter.
            string[] items = new string[0];
            int count = 0;
            int start = 0;
            int i = 0;
            while (i <= text.Length) {
                bool atEnd = i == text.Length;
                if (atEnd) {
                    int len = i - start;
                    items = Append(items, count, Slice(text, start, len));
                    count = count + 1;
                    start = i + 1;
                } else if (text[i] == "/") {
                    int len2 = i - start;
                    items = Append(items, count, Slice(text, start, len2));
                    count = count + 1;
                    start = i + 1;
                }
                i = i + 1;
            }
            return items;
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
