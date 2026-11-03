using Hydrogen.Compiler.Core;

namespace Hydrogen.Compiler.UI {
    // Package an exported WinUI 3 or AppKit runtime without invoking hyui --package.
    public class UIDesktopPackager {
        public static string Output(string path, string target) {
            if (target == "windows-x64" && !EndsWith(path, ".exe")) { return path + ".exe"; }
            if (target == "macos-x64" && !EndsWith(path, ".app")) { return path + ".app"; }
            return path;
        }

        public static string Backend(string output, string target) {
            if (target == "macos-x64") { return output + ".ui-staging/Contents/Resources/app/__hyui_backend"; }
            return output + ".ui-staging/app/__hyui_backend.exe";
        }

        private static string Source(string sdk, string target) {
            if (target == "windows-x64") {
                if (System.IO.File.Exists(sdk + "/windows-x64/hyui-runtime.json")) { return sdk + "/windows-x64"; }
                if (System.IO.File.Exists(sdk + "/hyui-runtime.json")) { return sdk; }
            } else {
                if (System.IO.File.Exists(sdk + "/macos-x64.app/Contents/hyui-runtime.json")) { return sdk + "/macos-x64.app/Contents"; }
                if (System.IO.File.Exists(sdk + "/Contents/hyui-runtime.json")) { return sdk + "/Contents"; }
            }
            return "";
        }

        public static string Prepare(string output, string target, string sdk) {
            string source = Source(sdk, target);
            if (source == "") { return "missing exported native runtime for " + target + "; provide --ui-sdk <runtime-directory>"; }
            string metadata = System.IO.File.ReadAllText(source + "/hyui-runtime.json");
            if (!Has(metadata, target) || !Has(metadata, target == "windows-x64" ? "winui3" : "appkit")) {
                return "native UI SDK renderer or target mismatch";
            }
            string host = target == "windows-x64" ? source + "/hyui.exe" : source + "/MacOS/hyui";
            string launcher = source + "/hyui-launcher.exe";
            if (!System.IO.File.Exists(host) ||
                (target == "windows-x64" && !System.IO.File.Exists(launcher))) {
                return "native UI SDK has no required platform renderer";
            }
            string stage = output + ".ui-staging";
            if (Exists(stage) || Exists(output + ".ui-backup") || Exists(output + ".ui-backup.runtime") ||
                Exists(output + ".ui-launcher")) { return "staging or backup path already exists"; }
            bool exists = Exists(output);
            if (IsLink(output) || IsLink(output + ".runtime")) { return "refusing to replace a linked output"; }
            if (target == "windows-x64") {
                if (exists != Exists(output + ".runtime") ||
                    (exists && !System.IO.File.Exists(output + ".runtime/hyui-runtime.json"))) {
                    return "refusing to overwrite an unowned Windows application";
                }
            } else if (exists && !System.IO.File.Exists(output + "/Contents/hyui-runtime.json")) {
                return "refusing to overwrite an unowned macOS application";
            }
            if (!MkDir(PathUtils.DirName(stage))) { return "cannot create desktop UI output directory"; }
            if (target == "macos-x64" && !MkDir(stage)) { return "cannot create macOS staging directory"; }
            string dest = target == "windows-x64" ? stage : stage + "/Contents";
            if (!Copy(source, dest)) { Abort(output); return "cannot stage native runtime"; }
            string app = target == "windows-x64" ? stage + "/app" : dest + "/Resources/app";
            if (!MkDir(app)) { Abort(output); return "cannot create bundled app directory"; }
            return "";
        }

        public static string Finish(string project, string output, string target) {
            HyprojManifest manifest = HyprojManifest.Load(project);
            string root = PathUtils.DirName(project);
            string app = target == "windows-x64" ? output + ".ui-staging/app" : output + ".ui-staging/Contents/Resources/app";
            string backend = Backend(output, target);
            if (!System.IO.File.Exists(backend)) { return "native UI backend not compiled"; }
            string executable = backend;
            if (backend[0] != "/") { executable = "./" + backend; }
            if (!System.Host.Process.IsWindows() && !Unix("chmod +x " + SQ(executable))) {
                return "cannot make native UI backend executable";
            }
            string error = CopyAsset(root, app, manifest.UI());
            if (error != "") { return error; }
            string[] assets = manifest.UIAssets();
            int i = 0;
            while (i < assets.Length) {
                error = CopyAsset(root, app, assets[i]);
                if (error != "") { return error; }
                i = i + 1;
            }
            System.IO.File.WriteAllText(app + "/__hyui_app.json",
                "{\"format\":1,\"document\":\"" + Escape(manifest.UI()) +
                "\",\"backend\":\"" + UIRuntimeManager.BackendName(target) +
                "\",\"target\":\"" + target + "\"}");
            if (target == "macos-x64") {
                // macOS launches the native AppKit renderer directly. Fix
                // old exported SDK manifests, and remove obsolete launchers.
                string contents = output + ".ui-staging/Contents";
                string plist = contents + "/Info.plist";
                if (!System.IO.File.Exists(plist)) {
                    return "exported AppKit application has no Info.plist";
                }
                string info = System.IO.File.ReadAllText(plist);
                if (Has(info, "<string>hyui-launcher</string>")) {
                    System.IO.File.WriteAllText(plist,
                        ReplaceAll(info, "<string>hyui-launcher</string>",
                            "<string>hyui</string>"));
                }
                Del(contents + "/MacOS/hyui-launcher", false);
            }
            bool old = Exists(output);
            if (old && !Move(output, output + ".ui-backup")) { return "cannot back up existing launcher"; }
            if (target == "windows-x64") {
                if (old && !Move(output + ".runtime", output + ".ui-backup.runtime")) {
                    Move(output + ".ui-backup", output);
                    return "cannot back up existing Windows runtime";
                }
                if (!Copy(output + ".ui-staging/hyui-launcher.exe", output + ".ui-launcher")) {
                    RestoreWindows(output, old, false);
                    return "cannot copy Windows launcher";
                }
                if (!Move(output + ".ui-staging", output + ".runtime")) {
                    RestoreWindows(output, old, false);
                    return "cannot publish Windows runtime";
                }
                if (!Move(output + ".ui-launcher", output)) {
                    RestoreWindows(output, old, true);
                    return "cannot publish Windows launcher";
                }
                if (old) { Del(output + ".ui-backup", false); Del(output + ".ui-backup.runtime", true); }
            } else {
                if (!Move(output + ".ui-staging", output)) {
                    if (old) { Move(output + ".ui-backup", output); }
                    return "cannot publish macOS application";
                }
                if (old) { Del(output + ".ui-backup", true); }
            }
            return "";
        }

        private static void RestoreWindows(string output, bool old, bool hasNewRuntime) {
            if (hasNewRuntime) { Del(output + ".runtime", true); }
            if (old) {
                Move(output + ".ui-backup.runtime", output + ".runtime");
                Move(output + ".ui-backup", output);
            }
        }

        public static void Abort(string output) {
            Del(output + ".ui-staging", true);
            Del(output + ".ui-launcher", false);
        }

        public static string CopyAsset(string root, string app, string relative) {
            if (relative == "" || relative[0] == "/" || relative == "." ||
                Has(relative, "..") || Has(relative, "\\") || Has(relative, ":") ||
                Has(relative, "__hyui")) { return "unsafe desktop UI asset path"; }
            string path = PathUtils.Join(root, relative);
            if (!Exists(path) || IsLink(path)) { return "missing or linked UI asset: " + relative; }
            if (System.Host.Process.IsWindows() &&
                PS("if((Get-ChildItem -LiteralPath " + PQ(path) +
                    " -Recurse -Force -ErrorAction Stop | Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0} | Measure-Object).Count -gt 0){exit 0}else{exit 1}")) {
                return "UI assets must not contain links";
            }
            if (!System.Host.Process.IsWindows() &&
                Unix("find -- " + SQ(path) + " -type l -print -quit | grep -q .")) {
                return "UI assets must not contain links";
            }
            string destination = PathUtils.Join(app, relative);
            if (!MkDir(PathUtils.DirName(destination)) || !Copy(path, destination)) {
                return "cannot copy UI asset: " + relative;
            }
            return "";
        }

        private static bool MkDir(string path) {
            if (System.Host.Process.IsWindows()) { return PS("[System.IO.Directory]::CreateDirectory(" + PQ(path) + ") | Out-Null"); }
            return Unix("mkdir -p -- " + SQ(path));
        }
        private static bool Copy(string source, string dest) {
            if (System.Host.Process.IsWindows()) { return PS("Copy-Item -LiteralPath " + PQ(source) + " -Destination " + PQ(dest) + " -Recurse -Force -ErrorAction Stop"); }
            return Unix("cp -R -- " + SQ(source) + " " + SQ(dest));
        }
        private static bool Move(string source, string dest) {
            if (System.Host.Process.IsWindows()) { return PS("Move-Item -LiteralPath " + PQ(source) + " -Destination " + PQ(dest) + " -ErrorAction Stop"); }
            return Unix("mv -- " + SQ(source) + " " + SQ(dest));
        }
        private static void Del(string path, bool directory) {
            if (System.Host.Process.IsWindows()) {
                PS("if(Test-Path -LiteralPath " + PQ(path) + "){Remove-Item -LiteralPath " + PQ(path) + " -Recurse -Force -ErrorAction Stop}");
            } else { Unix((directory ? "rm -rf -- " : "rm -f -- ") + SQ(path)); }
        }
        private static bool Exists(string path) {
            if (System.Host.Process.IsWindows()) { return PS("if(Test-Path -LiteralPath " + PQ(path) + "){exit 0}else{exit 1}"); }
            return Unix("test -e " + SQ(path));
        }
        private static bool IsLink(string path) {
            if (System.Host.Process.IsWindows()) {
                return PS("if((Get-Item -LiteralPath " + PQ(path) + " -ErrorAction SilentlyContinue).LinkType){exit 0}else{exit 1}");
            }
            return Unix("test -L " + SQ(path));
        }
        private static bool Unix(string command) { return System.Host.Process.Run(command) == 0; }
        private static bool PS(string command) {
            if (Has(command, "\"") || Has(command, "%") || Has(command, "\n")) { return false; }
            return System.Host.Process.Run("powershell.exe -NoProfile -NonInteractive -Command \"" + command + "\"") == 0;
        }
        private static string SQ(string value) {
            string output = "'";
            int i = 0;
            while (i < value.Length) {
                output = output + (value[i] == "'" ? "'\\''" : value[i]);
                i = i + 1;
            }
            return output + "'";
        }
        private static string PQ(string value) {
            string output = "'";
            int i = 0;
            while (i < value.Length) {
                output = output + (value[i] == "'" ? "''" : value[i]);
                i = i + 1;
            }
            return output + "'";
        }
        private static string Escape(string value) {
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
        private static string ReplaceAll(string value, string needle, string replacement) {
            string result = "";
            int i = 0;
            while (i < value.Length) {
                int j = 0;
                while (i + j < value.Length && j < needle.Length &&
                    value[i + j] == needle[j]) { j = j + 1; }
                if (j == needle.Length) {
                    result = result + replacement;
                    i = i + needle.Length;
                } else {
                    result = result + value[i];
                    i = i + 1;
                }
            }
            return result;
        }
        private static bool Has(string value, string text) {
            int i = 0;
            while (i + text.Length <= value.Length) {
                int j = 0;
                while (j < text.Length && value[i + j] == text[j]) { j = j + 1; }
                if (j == text.Length) { return true; }
                i = i + 1;
            }
            return false;
        }
        private static bool EndsWith(string value, string text) {
            if (text.Length > value.Length) { return false; }
            int i = 0;
            while (i < text.Length) {
                if (value[value.Length - text.Length + i] != text[i]) { return false; }
                i = i + 1;
            }
            return true;
        }
    }
}
