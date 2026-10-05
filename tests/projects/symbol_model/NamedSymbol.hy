namespace Compiler.Symbols {
    public class NamedSymbol : Symbol {
        protected string name;

        public NamedSymbol() {
            kind = "named";
            depth = depth + 1;
        }

        protected void SetName(string value) {
            name = value;
        }

        public string Name() {
            return name;
        }
    }
}
