using Hydrogen.Compiler.Core;

namespace Hydrogen.Compiler.UI {
    // Build one self-contained ELF file containing the native GTK4 window,
    // embedded HYUI documents/assets, and Hydrogen-compiled application code.
    // The backend ELF is launched from an in-memory fd until the native ABI
    // supports linking Hydrogen application methods into the GTK process.
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
                Run("command -v tar >/dev/null 2>&1") != 0 ||
                Run("command -v objcopy >/dev/null 2>&1") != 0 ||
                Run("pkg-config --exists gtk4") != 0) {
                return "single-file GTK4 builds need c++, tar, objcopy and GTK4 headers (Ubuntu: sudo apt install build-essential binutils pkg-config libgtk-4-dev)";
            }
            if (!System.IO.File.Exists("tools/hyui/linux_gtk_app.cpp")) {
                return "native GTK4 source not found: tools/hyui/linux_gtk_app.cpp (build from Hydrogen source root)";
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
            if (!executable && runtime) {
                return "refusing to overwrite an orphaned GTK4 runtime directory";
            }
            if (runtime) {
                if (!System.IO.File.Exists(output + ".runtime/hyui-runtime.json") ||
                    System.IO.File.ReadAllText(output + ".runtime/hyui-runtime.json") !=
                    "{\"format\":1,\"target\":\"linux-x64\",\"renderer\":\"gtk4-direct\"}") {
                    return "cannot overwrite an unowned or legacy UI runtime";
                }
            } else if (executable &&
                       Run("grep -aFq -- " + Quote("HYDROGEN_UI_SINGLE_FILE_V1") + " " +
                           Quote(output)) != 0) {
                return "refusing to overwrite an unowned executable; use another output path";
            }
            if (Run("mkdir -p -- " + Quote(stage + "/app")) != 0) {
                return "cannot stage single-file GTK4 application output";
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

            // All application files are embedded into the final ELF. The
            // archive and object exist only inside staging during compilation.
            // ustar rejects unsafe links/unsupported overlong paths at build
            // time rather than leaving the deployed app to guess at them.
            if (Run("tar --format=ustar -C " + Quote(app) +
                    " -cf " + Quote(stage + "/bundle.tar") + " .") != 0) {
                return "cannot archive Hydrogen application and HYUI resources";
            }
            if (Run("cd " + Quote(stage) +
                    " && objcopy -I binary -O elf64-x86-64 -B i386:x86-64 bundle.tar bundle.o") != 0) {
                return "cannot embed Hydrogen code and resources into ELF object";
            }

            string command = "c++ -std=c++20 -O2 -Wall -Wextra -Wl,-z,noexecstack " +
                Quote("tools/hyui/linux_gtk_app.cpp") + " " +
                Quote(stage + "/bundle.o") + " -o " +
                Quote(output + ".ui-launcher") +
                " $(pkg-config --cflags --libs gtk4)";
            if (Run(command) != 0) {
                return "single-file GTK4 compilation failed; check the C++ diagnostics and GTK4 development libraries";
            }
            if (Run("chmod +x -- " + Quote(output + ".ui-launcher")) != 0) {
                return "cannot make the generated single-file GTK4 application executable";
            }

            bool old = Exists(output);
            bool oldRuntime = Exists(output + ".runtime");
            if (old && Run("mv -- " + Quote(output) + " " + Quote(output + ".ui-backup")) != 0) {
                return "cannot back up the previous GTK4 executable";
            }
            if (oldRuntime &&
                Run("mv -- " + Quote(output + ".runtime") + " " +
                    Quote(output + ".ui-backup.runtime")) != 0) {
                if (old) { Run("mv -- " + Quote(output + ".ui-backup") + " " + Quote(output)); }
                return "cannot back up the previous GTK4 resources";
            }
            if (Run("mv -- " + Quote(output + ".ui-launcher") + " " + Quote(output)) != 0) {
                if (oldRuntime) {
                    Run("mv -- " + Quote(output + ".ui-backup.runtime") + " " +
                        Quote(output + ".runtime"));
                }
                if (old) { Run("mv -- " + Quote(output + ".ui-backup") + " " + Quote(output)); }
                return "cannot publish the single-file GTK4 executable";
            }
            Run("rm -rf -- " + Quote(stage));
            if (old) { Run("rm -f -- " + Quote(output + ".ui-backup")); }
            if (oldRuntime) { Run("rm -rf -- " + Quote(output + ".ui-backup.runtime")); }
            return "";
        }

        public static void Abort(string output) {
            Run("rm -rf -- " + Quote(output + ".ui-staging"));
            Run("rm -f -- " + Quote(output + ".ui-launcher"));
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
