namespace Compiler.Symbols {
    public class Symbol {
        protected string kind;
        protected int depth;

        public Symbol() {
            kind = "symbol";
            depth = 1;
        }

        public string Kind() {
            return kind;
        }

        public int Depth() {
            return depth;
        }
    }
}
