namespace Hydrogen.Compiler.IR {
    public class IrFunction {
        private IrMethod declaration;
        public void SetDeclaration(IrMethod value) { declaration = value; }
        private IrStatement body;
        public void SetBody(IrStatement value) {
            if (declaration != null) { declaration.SetBody(value); } else { body = value; }
        }
        public IrStatement Body() {
            if (declaration != null) { return declaration.Body(); }
            return body;
        }
        private string name;
        private string returnType;
        private string[] parameterTypes;

        public IrFunction(string inputName, string inputReturnType, string[] inputParameterTypes) {
            name = inputName;
            returnType = inputReturnType;
            parameterTypes = inputParameterTypes;
        }

        public string Name() {
            return name;
        }

        public string ReturnType() {
            return returnType;
        }

        public string[] ParameterTypes() {
            return parameterTypes;
        }

        public string ToDebugText() {
            string text = "  func " + name + "(";
            int i = 0;
            while (i < parameterTypes.Length) {
                if (i > 0) {
                    text = text + ", ";
                }
                text = text + parameterTypes[i];
                i = i + 1;
            }
            text = text + ") : " + returnType + "\n";
            if (Body() != null) { IrBodyPrinter printer = new IrBodyPrinter(); text = text + printer.Statement(Body(), "    "); }
            return text;
        }
    }
}

