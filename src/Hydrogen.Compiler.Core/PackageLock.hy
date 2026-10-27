namespace Hydrogen.Compiler.Core {
    public class PackageLock {
        public static string Render(string projectPath, ProjectClosure closure) {
            if (closure.Error() != "") { return ""; }
            string baseDir = PathUtils.DirName(PathUtils.Normalize(projectPath));
            string[] ids = closure.PackageIds();
            string[] versions = closure.PackageVersions();
            bool[] done = new bool[ids.Length];
            string result = "hydrogen-lock-v1\n";
            int count = 0;
            while (count < ids.Length) {
                int next = -1;
                int i = 0;
                while (i < ids.Length) {
                    if (!done[i] && (next < 0 || Less(ids[i], ids[next]))) { next = i; }
                    i = i + 1;
                }
                done[next] = true;
                string dir = PathUtils.Join(PathUtils.Join(PathUtils.Join(
                    baseDir, ".hylang/packages"), ids[next]), versions[next]);
                string archivePath = PathUtils.Join(dir, "package.hypkg");
                string manifestName = ids[next] + ".hyproj";
                string manifestPath = PathUtils.Join(dir, manifestName);
                if (!System.IO.File.Exists(archivePath) || !System.IO.File.Exists(manifestPath)) {
                    return "";
                }
                HyprojManifest manifest = HyprojManifest.Load(manifestPath);
                if (manifest.PackageId() != ids[next] || manifest.Version() != versions[next]) {
                    return "";
                }
                result = result + "package " + ids[next] + " " + versions[next] + " " +
                    Sha256.Hex(System.IO.File.ReadAllBytes(archivePath)) + "\n";
                result = result + "file " + manifestName + " " +
                    Sha256.Hex(System.IO.File.ReadAllBytes(manifestPath)) + "\n";
                string[] sources = manifest.Sources();
                int source = 0;
                while (source < sources.Length) {
                    if (!SafeName(sources[source])) { return ""; }
                    string path = PathUtils.Join(dir, sources[source]);
                    if (!System.IO.File.Exists(path)) { return ""; }
                    result = result + "file " + sources[source] + " " +
                        Sha256.Hex(System.IO.File.ReadAllBytes(path)) + "\n";
                    source = source + 1;
                }
                result = result + "end\n";
                count = count + 1;
            }
            return result;
        }

        public static bool Verify(string projectPath, ProjectClosure closure) {
            if (closure.PackageIds().Length == 0) { return true; }
            string path = PathUtils.Join(PathUtils.DirName(PathUtils.Normalize(projectPath)), "hy.lock");
            if (!System.IO.File.Exists(path)) { return false; }
            string expected = Render(projectPath, closure);
            return expected != "" && System.IO.File.ReadAllText(path) == expected;
        }

        private static bool SafeName(string name) {
            if (name == "" || name == "." || name == "..") { return false; }
            int i = 0;
            while (i < name.Length) {
                if (name[i] == "/" || name[i] == "\\" || name[i] == " " ||
                    name[i] == "\n" || name[i] == "\r") { return false; }
                i = i + 1;
            }
            return true;
        }

        private static bool Less(string left, string right) {
            int i = 0;
            while (i < left.Length && i < right.Length) {
                if (left[i] != right[i]) {
                    string order = "-.0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz";
                    return Position(order, left[i]) < Position(order, right[i]);
                }
                i = i + 1;
            }
            return left.Length < right.Length;
        }

        private static int Position(string text, string ch) {
            int i = 0;
            while (i < text.Length) { if (text[i] == ch) { return i; } i = i + 1; }
            return text.Length;
        }
    }
}
