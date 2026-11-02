using Hydrogen.Compiler.Core;

namespace Hydrogen.Compiler.UI {
    // Linux native packaging. The compiler builds the Hydrogen backend itself.
    // This module only stages the OS host and application assets.
    public class UIPackager {
        public static string Prepare(string projectPath, string output, string target) {
            if (target != "linux-x64") {
                return "self-hosted UI packaging currently supports linux-x64 only";
            }
            if (!System.IO.File.Exists("build/bootstrap/hyui-native") ||
                !System.IO.File.Exists("build/bootstrap/hyui-launcher")) {
                return "native UI SDK missing: build with Qt 6.8+ and HYDROGEN_BUILD_UI=ON";
            }
            string stage = output + ".ui-staging";
            if (Run("test -e " + Quote(output)) == 0 ||
                Run("test -e " + Quote(output + ".runtime")) == 0 ||
                Run("test -e " + Quote(stage)) == 0) {
                return "UI output or staging directory already exists: " + output;
            }
            if (Run("mkdir -p -- " + Quote(stage + "/app")) != 0) {
                return "cannot create UI runtime directory";
            }
            return "";
        }

        public static string Finish(string projectPath, string output, string target) {
            if (target != "linux-x64") { return "unsupported UI target"; }
            HyprojManifest manifest = HyprojManifest.Load(projectPath);
            string root = PathUtils.DirName(projectPath);
            string runtime = output + ".ui-staging";
            string app = runtime + "/app";
            string[] files = manifest.UIAssets();
            string error = CopyResource(root, app, manifest.UI());
            if (error != "") { return error; }
            int i = 0;
            while (i < files.Length) {
                error = CopyResource(root, app, files[i]);
                if (error != "") { return error; }
                i = i + 1;
            }
            if (Run("cp -- " + Quote("build/bootstrap/hyui-native") + " " + Quote(runtime + "/hyui")) != 0) {
                return "failed to copy GTK4 native host";
            }
            if (Run("mkdir -p -- " + Quote(runtime + "/lib")) != 0) {
                return "failed to stage native UI libraries";
            }
            // GTK4 remains a system library; bundle Qt Core's nonvisual runtime
            // dependencies, matching the native packager's Linux deployment rule.
            string qtDependencies = "ldd " + Quote(runtime + "/hyui") +
                " | awk '$1 ~ /^(libQt6Core[.]so|libicu|libdouble-conversion|libb2[.]so|libpcre2-16[.]so)/ && $2 == \"=>\" { print $3 }'" +
                " | while IFS= read -r lib; do cp -L -- \"$lib\" " + Quote(runtime + "/lib/") +
                " || exit 1; done";
            if (Run(qtDependencies) != 0) { return "failed to bundle Qt Core runtime"; }
            System.IO.File.WriteAllText(runtime + "/qt.conf", "[Paths]\\nPrefix=.\\nLibraries=lib\\n");
            System.IO.File.WriteAllText(app + "/__hyui_app.json",
                "{\"format\":1,\"document\":\"" + JsonEscape(manifest.UI()) +
                "\",\"backend\":\"__hyui_backend\",\"target\":\"linux-x64\"}");
            System.IO.File.WriteAllText(runtime + "/hyui-runtime.json",
                "{\"format\":1,\"target\":\"linux-x64\",\"renderer\":\"gtk4\"}");
            if (Run("cp -- " + Quote("build/bootstrap/hyui-launcher") + " " + Quote(output + ".ui-launcher")) != 0) {
                return "failed to stage application launcher";
            }
            if (Run("mv -- " + Quote(runtime) + " " + Quote(output + ".runtime")) != 0 ||
                Run("mv -- " + Quote(output + ".ui-launcher") + " " + Quote(output)) != 0) {
                return "failed to publish native UI application";
            }
            return "";
        }

        private static string CopyResource(string root, string app, string relative) {
            if (!SafeRelative(relative)) { return "invalid UI asset path: " + relative; }
            string source = PathUtils.Join(root, relative);
            string destination = PathUtils.Join(app, relative);
            // Never package links pointing outside the project.
            if (Run("find -- " + Quote(source) + " -type l -print -quit | grep -q .") == 0) {
                return "symlinked UI assets are not supported: " + relative;
            }
            string parent = PathUtils.DirName(destination);
            if (Run("mkdir -p -- " + Quote(parent)) != 0 ||
                Run("cp -R -- " + Quote(source) + " " + Quote(destination)) != 0) {
                return "failed to package UI asset: " + relative;
            }
            return "";
        }

        private static bool SafeRelative(string value) {
            if (value.Length == 0 || value[0] == "/" || value[0] == "\\") { return false; }
            if (value == ".." || value == ".") { return false; }
            if (Contains(value, "../") || Contains(value, "/..") || Contains(value, "\\") ||
                Contains(value, ":") || Contains(value, "//")) { return false; }
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

        private static string JsonEscape(string value) {
            string output = "";
            int i = 0;
            while (i < value.Length) {
                if (value[i] == "\\") { output = output + "\\\\"; }
                else if (value[i] == "\"") { output = output + "\\\""; }
                else { output = output + value[i]; }
                i = i + 1;
            }
            return output;
        }

        private static string Quote(string value) {
            string output = "'";
            int i = 0;
            while (i < value.Length) {
                if (value[i] == "'") { output = output + "'\\''"; }
                else { output = output + value[i]; }
                i = i + 1;
            }
            return output + "'";
        }

        private static int Run(string command) {
            return System.Host.Process.Run(command);
        }
    }
}
