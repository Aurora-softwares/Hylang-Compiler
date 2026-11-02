using Hydrogen.Compiler.Core;

namespace Hydrogen.Compiler.UI {
    public class UIProjectBuilder {
        // This provides a safe pure-Hydrogen entry point for future packaging.
        // It does not replace the production build path before runtime parity.
        public static string Preflight(string projectPath) {
            if (!System.IO.File.Exists(projectPath)) { return "project not found: " + projectPath; }
            HyprojManifest manifest = HyprojManifest.Load(projectPath);
            if (manifest.Format() != 2 || !manifest.HasUI()) {
                return "expected a format 2 project with a ui document";
            }
            string target = UIRuntimeManager.Target(manifest.Type());
            if (target == "") { return "UI projects require a desktop executable target"; }
            string uiPath = manifest.UI();
            if (uiPath == "" || uiPath[0] == "/" || uiPath[0] == "\\" ||
                Contains(uiPath, "..") || Contains(uiPath, "\\") || Contains(uiPath, ":")) {
                return "UI document path must be project-relative";
            }
            string resolved = PathUtils.Join(PathUtils.DirName(projectPath), uiPath);
            string parent = PathUtils.Normalize(PathUtils.DirName(projectPath));
            if (resolved == parent || StartsWith(resolved, parent + "/../")) {
                return "UI document escapes project directory";
            }
            return UIValidator.Preflight(resolved);
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

        private static bool StartsWith(string value, string prefix) {
            if (value.Length < prefix.Length) { return false; }
            int i = 0;
            while (i < prefix.Length) {
                if (value[i] != prefix[i]) { return false; }
                i = i + 1;
            }
            return true;
        }
    }
}
