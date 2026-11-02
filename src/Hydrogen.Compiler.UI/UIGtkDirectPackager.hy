using Hydrogen.Compiler.Core;

namespace Hydrogen.Compiler.UI {
    // Compile one native GTK4 frontend for each Linux UI project. This does
    // not invoke hyui-native, hyui-launcher, Qt, or a precompiled UI host.
    // The compiled Hydrogen event backend remains separate until the final
    // single-process integration milestone.
    public class UIGtkDirectPackager {
        private static int Run(string command) {
            return System.Host.Process.Run(command);
        }

        private static string Quote(string value) {
            string result = "'";
            int i = 0;
            while (i < value.Length) {
                if (value[i] == "'") { result = result + "'\\''"; }
                else { result = result + value[i]; }
                i = i + 1;
            }
            return result + "'";
        }

        private static bool Exists(string file) {
            return Run("test -e " + Quote(file)) == 0;
        }

        public static string Backend(string output) {
            return output + ".ui-staging/app/__hyui_backend";
        }

        public static string Prepare(string output) {
            if (Run("command -v c++ >/dev/null 2>&1") != 0 ||
                Run("command -v pkg-config >/dev/null 2>&1") != 0 ||
                Run("pkg-config --exists gtk4") != 0) {
                return "native GTK4 compilation needs a C++ compiler, pkg-config, and GTK4 development headers (Ubuntu: sudo apt install build-essential pkg-config libgtk-4-dev)";
            }
            if (!System.IO.File.Exists("tools/hyui/linux_gtk_app.cpp")) {
                return "native GTK4 source not found: tools/hyui/linux_gtk_app.cpp (run from Hydrogen source root)";
            }
            string stage = output + ".ui-staging";
            if (Exists(stage) || Exists(output + ".ui-launcher") || Exists(output + ".ui-backup") ||
                Exists(output + ".ui-backup.runtime")) {
                return "GTK4 output has leftover staging or backup paths: " + output;
            }
            if (Run("test -L " + Quote(output)) == 0 ||
                Run("test -L " + Quote(output + ".runtime")) == 0) {
                return "refusing a linked native GTK4 output";
            }
            bool executable = Exists(output);
            bool runtime = Exists(output + ".runtime");
            if (executable != runtime) {
                return "refusing to overwrite an incomplete or unowned native UI package";
            }
            if (executable && !System.IO.File.Exists(output + ".runtime/hyui-runtime.json")) {
                return "refusing to overwrite an unowned desktop application";
            }
            if (executable && System.IO.File.ReadAllText(output + ".runtime/hyui-runtime.json") !=
                "{\"format\":1,\"target\":\"linux-x64\",\"renderer\":\"gtk4-direct\"}") {
                return "cannot overwrite a non-direct GTK4 application; use a different output path";
            }
            if (Run("mkdir -p -- " + Quote(stage + "/app")) != 0) {
                return "cannot stage GTK4 application output";
            }
            return "";
        }

        public static string Finish(string projectPath, string output) {
            HyprojManifest manifest = HyprojManifest.Load(projectPath);
            string stage = output + ".ui-staging";
            string app = stage + "/app";
            string backend = app + "/__hyui_backend";
            if (!System.IO.File.Exists(backend) || Run("chmod +x -- " + Quote(backend)) != 0) {
                return "Hydrogen UI backend was not compiled";
            }
            string root = PathUtils.DirName(projectPath);
            string document = manifest.UI();
            if (!SafeRelative(document)) { return "invalid GTK4 document path"; }
            string error = CopyResource(root, app, document);
            if (error != "") { return error; }
            string[] assets = manifest.UIAssets();
            int i = 0;
            while (i < assets.Length) {
                error = CopyResource(root, app, assets[i]);
                if (error != "") { return error; }
                i = i + 1;
            }
            System.IO.File.WriteAllText(app + "/__hyui_document", document + "\n");
            System.IO.File.WriteAllText(stage + "/hyui-runtime.json",
                "{\"format\":1,\"target\":\"linux-x64\",\"renderer\":\"gtk4-direct\"}");

            // The application-specific GTK4 executable is built here rather
            // than shipped as another host program. The backend and data are
            // private resources beside the executable during this milestone.
            string command = "c++ -std=c++20 -O2 -Wall -Wextra " +
                Quote("tools/hyui/linux_gtk_app.cpp") + " -o " +
                Quote(output + ".ui-launcher") +
                " $(pkg-config --cflags --libs gtk4)";
            if (Run(command) != 0) {
                return "GTK4 application compilation failed (check C++ diagnostics and installed GTK4 development libraries)";
            }
            if (Run("chmod +x -- " + Quote(output + ".ui-launcher")) != 0) {
                return "cannot make the native GTK4 application executable";
            }

            bool old = Exists(output);
            if (old) {
                if (Run("mv -- " + Quote(output) + " " + Quote(output + ".ui-backup")) != 0) {
                    return "cannot back up the previous GTK4 executable";
                }
                if (Run("mv -- " + Quote(output + ".runtime") + " " +
                        Quote(output + ".ui-backup.runtime")) != 0) {
                    Run("mv -- " + Quote(output + ".ui-backup") + " " + Quote(output));
                    return "cannot back up the previous GTK4 resources";
                }
            }
            if (Run("mv -- " + Quote(stage) + " " + Quote(output + ".runtime")) != 0) {
                Restore(output, old, false);
                return "cannot publish GTK4 application resources";
            }
            if (Run("mv -- " + Quote(output + ".ui-launcher") + " " + Quote(output)) != 0) {
                Restore(output, old, true);
                return "cannot publish GTK4 executable";
            }
            if (old) {
                Run("rm -f -- " + Quote(output + ".ui-backup"));
                Run("rm -rf -- " + Quote(output + ".ui-backup.runtime"));
            }
            return "";
        }

        public static void Abort(string output) {
            Run("rm -rf -- " + Quote(output + ".ui-staging"));
            Run("rm -f -- " + Quote(output + ".ui-launcher"));
        }

        private static void Restore(string output, bool old, bool newRuntime) {
            if (newRuntime) { Run("rm -rf -- " + Quote(output + ".runtime")); }
            if (old) {
                Run("mv -- " + Quote(output + ".ui-backup.runtime") + " " +
                    Quote(output + ".runtime"));
                Run("mv -- " + Quote(output + ".ui-backup") + " " + Quote(output));
            }
        }

        private static string CopyResource(string root, string destination, string relative) {
            if (!SafeRelative(relative)) { return "invalid UI asset path: " + relative; }
            string source = PathUtils.Join(root, relative);
            if (!Exists(source) || Run("test -L " + Quote(source)) == 0 ||
                Run("find -- " + Quote(source) + " -type l -print -quit | grep -q .") == 0) {
                return "missing or linked GTK4 asset: " + relative;
            }
            string target = PathUtils.Join(destination, relative);
            if (Run("mkdir -p -- " + Quote(PathUtils.DirName(target))) != 0 ||
                Run("cp -R -- " + Quote(source) + " " + Quote(target)) != 0) {
                return "cannot copy GTK4 asset: " + relative;
            }
            return "";
        }

        private static bool SafeRelative(string value) {
            if (value.Length == 0 || value[0] == "/" || value[0] == "\\") { return false; }
            if (value == "." || value == "..") { return false; }
            return !Has(value, "..") && !Has(value, "\\") && !Has(value, ":") &&
                !Has(value, "//") && !Has(value, "\n");
        }

        private static bool Has(string value, string needle) {
            int i = 0;
            while (i + needle.Length <= value.Length) {
                int j = 0;
                while (j < needle.Length && value[i + j] == needle[j]) { j = j + 1; }
                if (j == needle.Length) { return true; }
                i = i + 1;
            }
            return false;
        }
    }
}
