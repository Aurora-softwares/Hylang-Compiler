namespace Hydrogen.Compiler.IR {
    public class IrModule {
        private IrFunction[] functions;

        public IrModule(IrFunction[] inputFunctions) {
            functions = inputFunctions;
        }

        public IrFunction[] Functions() {
            return functions;
        }

        public string ToDebugText() {
            string text = "IrModule\n";
            int i = 0;
            while (i < functions.Length) {
                text = text + functions[i].ToDebugText();
                i = i + 1;
            }
            return text;
        }
    }
}

