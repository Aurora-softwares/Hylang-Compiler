namespace Compiler.Symbols {
    public class MethodSymbol : NamedSymbol {
        private int parameterCount;

        public MethodSymbol(string value, int count) {
            kind = "method";
            depth = depth + 1;
            SetName(value);
            parameterCount = count;
        }

        public int ParameterCount() {
            return parameterCount;
        }
    }
}
