namespace Compiler.Symbols {
    public class TypeSymbol : NamedSymbol {
        public TypeSymbol(string value) {
            kind = "type";
            depth = depth + 1;
            SetName(value);
        }
    }
}
