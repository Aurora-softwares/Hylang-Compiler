using Hydrogen.Compiler.Core;

namespace Hydrogen.Compiler.UI {
    public class UIRuntimeManager {
        public static string Target(string projectType) {
            if (projectType == "exe" || projectType == "linux" || projectType == "linux-x64") { return "linux-x64"; }
            if (projectType == "windows" || projectType == "windows-x64") { return "windows-x64"; }
            if (projectType == "macos" || projectType == "macos-x64") { return "macos-x64"; }
            return "";
        }

        public static string NativeRuntimeDirectory(string output, string target) {
            if (target == "macos-x64") { return output + ".app/Contents"; }
            return output + ".runtime";
        }

        public static string BackendName(string target) {
            if (target == "windows-x64") { return "__hyui_backend.exe"; }
            return "__hyui_backend";
        }
    }
}
