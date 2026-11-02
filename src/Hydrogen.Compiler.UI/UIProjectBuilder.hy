using Hydrogen.Compiler.Core;

namespace Hydrogen.Compiler.UI {
    public class UIProjectBuilder {
        // Document preflight runs inside every self-hosted compiler stage.
        // The OS-native renderer is optional for preflight but is still needed
        // when packaging and running graphical applications.
        public static string Preflight(string projectPath, string sdkRoot) {
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
            string error = UIValidator.Preflight(resolved);
            if (error != "") { return error; }
            // Run the native validator only when installed. This keeps
            // compiler-side UI validation usable on clean stage1/2/3 installs
            // even when the platform-native UI SDK has not been exported.
            string host = UIRuntimeManager.NativeHost(sdkRoot);
            if (System.IO.File.Exists(host) && !System.Host.Process.IsWindows() &&
                System.Host.Process.Run(Quote(host) + " --validate --document " + Quote(resolved)) != 0) {
                return "native .hyui validation failed: " + resolved;
            }
            return "";
        }

        private static string Quote(string value) {
            string quoted = "'";
            int i = 0;
            while (i < value.Length) {
                if (value[i] == "'") { quoted = quoted + "'\\''"; }
                else { quoted = quoted + value[i]; }
                i = i + 1;
            }
            return quoted + "'";
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
