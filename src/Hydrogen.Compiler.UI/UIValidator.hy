namespace Hydrogen.Compiler.UI {
    public class UIValidator {
        // Preflight only: comprehensive attributes, event and placement rules
        // remain enforced by the existing native document parser.
        public static string Preflight(string documentPath) {
            if (!System.IO.File.Exists(documentPath)) { return "UI document not found: " + documentPath; }
            UIDocumentParser parser = new UIDocumentParser(System.IO.File.ReadAllText(documentPath));
            if (!parser.Scan()) { return parser.Error(); }
            return "";
        }
    }
}
