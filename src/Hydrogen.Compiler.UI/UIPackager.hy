namespace Hydrogen.Compiler.UI {
    public class UIPackager {
        // Deliberately do not invoke an external hyui binary here. This module
        // will own atomic package publication once native runtime resource
        // embedding and reliable file-tree operations are implemented.
        public static string NotYetAvailable(string target) {
            return "Self-hosted UI packaging for " + target +
                " is not enabled yet; keep the existing native packager until parity tests pass";
        }
    }
}
