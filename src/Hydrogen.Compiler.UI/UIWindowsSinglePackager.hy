using Hydrogen.Compiler.Core;

namespace Hydrogen.Compiler.UI {
    // Build an unpackaged, self-contained WinUI 3 EXE containing the compiled
    // Hydrogen backend, HYUI XML and app assets as an embedded assembly resource.
    // WinUI/.NET extracts runtime files at first launch as required by Windows.
    // Hydrogen event handlers still run as a child until native ABI integration.
    public class UIWindowsSinglePackager {
        private static int Run(string command) {
            return System.Host.Process.Run(command);
        }
        private static string PQ(string value) {
            string result = "'";
            int i = 0;
            while (i < value.Length) {
                result = result + (value[i] == "'" ? "''" : value[i]);
                i = i + 1;
            }
            return result + "'";
        }
        private static bool PS(string script) {
            if (Has(script, "\"") || Has(script, "%") || Has(script, "\n")) { return false; }
            return Run("powershell.exe -NoProfile -NonInteractive -Command \"" + script + "\"") == 0;
        }
        private static bool Has(string text, string needle) {
            int i = 0;
            while (i + needle.Length <= text.Length) {
                int j = 0;
                while (j < needle.Length && text[i + j] == needle[j]) { j = j + 1; }
                if (j == needle.Length) { return true; }
                i = i + 1;
            }
            return false;
        }
        private static bool Exists(string path) {
            return PS("if (Test-Path -LiteralPath " + PQ(path) +
                ") { exit 0 } else { exit 1 }");
        }
        public static string Backend(string output) {
            return output + ".ui-staging/app/__hyui_backend.exe";
        }
        public static string Prepare(string output) {
            if (!System.Host.Process.IsWindows()) { return "WinUI single-file compilation requires a Windows host"; }
            if (!System.IO.File.Exists("tools/hyui/windows/Hyui.WinUI.csproj")) {
                return "WinUI project sources are not available; build from the Hydrogen source root";
            }
            if (Run("dotnet --version") != 0) { return "WinUI single-file compilation requires .NET SDK 8 or later"; }
            if (Exists(output)) {
                return "refusing to overwrite an existing Windows executable; choose an unused -o path";
            }
            string stage = output + ".ui-staging";
            if (Exists(stage) || Exists(output + ".runtime") || Exists(output + ".ui-backup")) {
                return "refusing to overwrite an existing or incomplete UI output";
            }
            if (!PS("[System.IO.Directory]::CreateDirectory(" + PQ(stage + "/app") +
                    ") | Out-Null")) {
                return "cannot stage WinUI single-file application";
            }
            return "";
        }
        public static string Finish(string project, string output) {
            HyprojManifest manifest = HyprojManifest.Load(project);
            string stage = output + ".ui-staging";
            string app = stage + "/app";
            if (!System.IO.File.Exists(Backend(output))) {
                return "Hydrogen Windows UI backend was not compiled";
            }
            string root = PathUtils.DirName(project);
            string error = UIDesktopPackager.CopyAsset(root, app, manifest.UI());
            if (error != "") { return error; }
            string[] assets = manifest.UIAssets();
            int i = 0;
            while (i < assets.Length) {
                error = UIDesktopPackager.CopyAsset(root, app, assets[i]);
                if (error != "") { return error; }
                i = i + 1;
            }
            System.IO.File.WriteAllText(app + "/__hyui_app.json",
                "{\"format\":1,\"document\":\"" + Escape(manifest.UI()) +
                "\",\"backend\":\"__hyui_backend.exe\",\"target\":\"windows-x64\"}");
            string archive = stage + "/bundle.zip";
            string compressed = "Compress-Archive -Path (Join-Path " + PQ(app) +
                " '*') -DestinationPath " + PQ(archive) + " -Force -ErrorAction Stop";
            if (!PS(compressed)) { return "could not embed WinUI document, assets and backend"; }

            // Windows App SDK 1.5+ supports single-file self-contained WinUI
            // desktop programs. These properties are checked by its SDK.
            string publish = "$uiArchive = (Resolve-Path -LiteralPath " +
                PQ(archive) + ").Path; & dotnet publish " +
                PQ("tools/hyui/windows/Hyui.WinUI.csproj") +
                " -c Release -r win-x64 -p:Platform=x64" +
                " -p:WindowsPackageType=None -p:WindowsAppSDKSelfContained=true" +
                " -p:SelfContained=true -p:EnableMsixTooling=true" +
                " -p:IncludeAllContentForSelfExtract=true -p:PublishSingleFile=true" +
                " ('-p:HydrogenUiArchive=' + $uiArchive)" +
                " -o " + PQ(stage + "/publish") +
                "; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }";
            if (!PS(publish)) {
                return "WinUI single-file publish failed; check dotnet publish diagnostics";
            }
            string generated = stage + "/publish/Hyui.WinUI.exe";
            if (!System.IO.File.Exists(generated)) { return "WinUI publish did not produce Hyui.WinUI.exe"; }

            if (!PS("Move-Item -LiteralPath " + PQ(generated) + " -Destination " +
                    PQ(output) + " -ErrorAction Stop")) {
                return "cannot publish standalone WinUI EXE";
            }
            Abort(output);
            return "";
        }
        public static void Abort(string output) {
            string stage = output + ".ui-staging";
            // Only clear compiler-owned staging paths, never an output file.
            PS("if (Test-Path -LiteralPath " + PQ(stage) +
                ") { Remove-Item -LiteralPath " + PQ(stage) + " -Recurse -Force -ErrorAction Stop }");
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
    }
}
