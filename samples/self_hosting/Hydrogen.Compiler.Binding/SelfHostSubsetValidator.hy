using Hydrogen.Compiler.Diagnostics;
using Hydrogen.Compiler.Text;

namespace Hydrogen.Compiler.Binding {
    public class SelfHostSubsetValidator {
        public bool Validate(SourceText source, DiagnosticBag diagnostics) {
            // The parser and binder own real language diagnostics. This validator remains
            // as a compatibility hook for older call sites, but it must not reject source
            // by substring because compiler identifiers and string literals can contain
            // words such as "try" or "List<".
            return !diagnostics.HasErrors();
        }
    }
}
