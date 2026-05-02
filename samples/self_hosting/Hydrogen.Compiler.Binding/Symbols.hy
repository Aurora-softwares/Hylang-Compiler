namespace Hydrogen.Compiler.Binding {
    public class TypeSymbol {
        private string name;

        public TypeSymbol(string inputName) {
            name = inputName;
        }

        public string Name() {
            return name;
        }
    }

    public class ParameterSymbol {
        private string name;
        private TypeSymbol type;

        public ParameterSymbol(string inputName, TypeSymbol inputType) {
            name = inputName;
            type = inputType;
        }

        public string Name() {
            return name;
        }

        public TypeSymbol Type() {
            return type;
        }
    }

    public class MethodSymbol {
        private string name;
        private bool isStatic;
        private TypeSymbol returnType;
        private ParameterSymbol[] parameters;

        public MethodSymbol(string inputName, bool inputIsStatic, TypeSymbol inputReturnType, ParameterSymbol[] inputParameters) {
            name = inputName;
            isStatic = inputIsStatic;
            returnType = inputReturnType;
            parameters = inputParameters;
        }

        public string Name() {
            return name;
        }

        public bool IsStatic() {
            return isStatic;
        }

        public TypeSymbol ReturnType() {
            return returnType;
        }

        public ParameterSymbol[] Parameters() {
            return parameters;
        }
    }
}

