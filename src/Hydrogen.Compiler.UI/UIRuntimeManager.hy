using Hydrogen.Compiler.Core;

namespace Hydrogen.Compiler.UI {
    public class UIRuntimeManager {
        public static string Target(string projectType) {
            if (projectType == "exe" || projectType == "linux" || projectType == "linux-x64") { return "linux-x64"; }
            if (projectType == "windows" || projectType == "windows-x64") { return "windows-x64"; }
            if (projectType == "macos" || projectType == "macos-x64") { return "macos-x64"; }
            return "";
        }

        // Explicit SDK directory supports installed and relocated compilers.
        // The default preserves repository bootstrap behaviour.
        public static string SdkRoot(string requested) {
            if (requested != "") { return requested; }
            if (System.IO.File.Exists("build/bootstrap/hydrogen-gtk-app")) { return "build/bootstrap"; }
            if (System.IO.File.Exists("build/ui/hydrogen-gtk-app")) { return "build/ui"; }
            if (System.IO.File.Exists("build/hydrogen-gtk-app")) { return "build"; }
            if (System.IO.File.Exists("build/bootstrap/hyui-native")) { return "build/bootstrap"; }
            if (System.IO.File.Exists("build/hyui-native")) { return "build"; }
            return "build/bootstrap";
        }

        public static string PackageSdk(string requested, string target) {
            if (requested != "") { return requested; }
            if (target == "windows-x64") {
                if (System.IO.File.Exists("build/bootstrap/native-sdk/windows-x64/hyui-runtime.json")) {
                    return "build/bootstrap/native-sdk";
                }
                if (System.IO.File.Exists("build/native-sdk/windows-x64/hyui-runtime.json")) {
                    return "build/native-sdk";
                }
            }
            if (target == "macos-x64") {
                if (System.IO.File.Exists("build/bootstrap/native-sdk/macos-x64.app/Contents/hyui-runtime.json")) {
                    return "build/bootstrap/native-sdk";
                }
                if (System.IO.File.Exists("build/native-sdk/macos-x64.app/Contents/hyui-runtime.json")) {
                    return "build/native-sdk";
                }
            }
            return SdkRoot("");
        }

        public static string NativeGtkApplication(string sdkRoot) {
            return Hydrogen.Compiler.Core.PathUtils.Join(sdkRoot, "hydrogen-gtk-app");
        }

        public static string NativeHost(string sdkRoot) {
            return Hydrogen.Compiler.Core.PathUtils.Join(sdkRoot, "hyui-native");
        }

        public static string NativeLauncher(string sdkRoot) {
            return Hydrogen.Compiler.Core.PathUtils.Join(sdkRoot, "hyui-launcher");
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
