using Hydrogen.Compiler.Diagnostics;
using Hydrogen.Compiler.Syntax;

namespace Hydrogen.Compiler.Binding {
    public class MethodSignature {
        private string name;
        private bool isStatic;
        private TypeSymbol returnType;
        private TypeSymbol[] parameterTypes;

        public MethodSignature(string inputName, bool inputIsStatic, TypeSymbol inputReturnType, TypeSymbol[] inputParameterTypes) {
            name = inputName;
            isStatic = inputIsStatic;
            returnType = inputReturnType;
            parameterTypes = inputParameterTypes;
        }

        public string Name() { return name; }
        public bool IsStatic() { return isStatic; }
        public TypeSymbol ReturnType() { return returnType; }
        public TypeSymbol[] ParameterTypes() { return parameterTypes; }
    }

    public class TypeInfo {
        private string name;
        private MethodSignature[] methods;

        public TypeInfo(string inputName, MethodSignature[] inputMethods) {
            name = inputName;
            methods = inputMethods;
        }

        public string Name() { return name; }
        public MethodSignature[] Methods() { return methods; }

        public MethodSignature TryGetMethod(string methodName) {
            int i = 0;
            while (i < methods.Length) {
                if (methods[i].Name() == methodName) {
                    return methods[i];
                }
                i = i + 1;
            }
            return null;
        }
    }

    public class GlobalSymbolTable {
        private TypeInfo[] types;

        public GlobalSymbolTable(TypeInfo[] inputTypes) {
            types = inputTypes;
        }

        public TypeInfo[] Types() { return types; }

        public TypeInfo TryGetType(string typeName) {
            int i = 0;
            while (i < types.Length) {
                if (types[i].Name() == typeName) {
                    return types[i];
                }
                i = i + 1;
            }
            return null;
        }

        public MethodSignature TryGetMethodInType(string typeName, string methodName) {
            TypeInfo type = TryGetType(typeName);
            if (type == null) { return null; }
            return type.TryGetMethod(methodName);
        }

        public MethodSignature TryFindFirstMethodByName(string methodName) {
            int i = 0;
            while (i < types.Length) {
                MethodSignature found = types[i].TryGetMethod(methodName);
                if (found != null) { return found; }
                i = i + 1;
            }
            return null;
        }

        public static GlobalSymbolTable Build(CompilationUnitSyntax root, DiagnosticBag diagnostics) {
            string[] typeNames = new string[0];
            TypeInfo[] typeInfos = new TypeInfo[0];
            int typeCount = 0;

            ClassDeclarationSyntax[] topClasses = root.Classes();
            int i = 0;
            while (i < topClasses.Length) {
                string name = topClasses[i].Name();
                if (Contains(typeNames, name)) {
                    diagnostics.Report(1, 1, "duplicate type: " + name);
                } else {
                    TypeInfo info = BuildTypeInfo(topClasses[i], diagnostics);
                    typeNames = AppendString(typeNames, typeCount, name);
                    typeInfos = AppendType(typeInfos, typeCount, info);
                    typeCount = typeCount + 1;
                }
                i = i + 1;
            }

            NamespaceDeclarationSyntax[] namespaces = root.Namespaces();
            int n = 0;
            while (n < namespaces.Length) {
                ClassDeclarationSyntax[] classes = namespaces[n].Classes();
                int c = 0;
                while (c < classes.Length) {
                    string name2 = classes[c].Name();
                    if (Contains(typeNames, name2)) {
                        diagnostics.Report(1, 1, "duplicate type: " + name2);
                    } else {
                        TypeInfo info2 = BuildTypeInfo(classes[c], diagnostics);
                        typeNames = AppendString(typeNames, typeCount, name2);
                        typeInfos = AppendType(typeInfos, typeCount, info2);
                        typeCount = typeCount + 1;
                    }
                    c = c + 1;
                }
                n = n + 1;
            }

            return new GlobalSymbolTable(typeInfos);
        }

        private static TypeInfo BuildTypeInfo(ClassDeclarationSyntax cl, DiagnosticBag diagnostics) {
            MethodDeclarationSyntax[] decls = cl.Methods();
            MethodSignature[] methods = new MethodSignature[0];
            string[] methodNames = new string[0];
            int methodCount = 0;

            int i = 0;
            while (i < decls.Length) {
                MethodDeclarationSyntax decl = decls[i];
                if (Contains(methodNames, decl.Name())) {
                    diagnostics.Report(1, 1, "duplicate method in type '" + cl.Name() + "': " + decl.Name());
                } else {
                    TypeSymbol returnType = new TypeSymbol(decl.ReturnType().DisplayName());
                    ParameterSyntax[] ps = decl.Parameters();
                    TypeSymbol[] paramTypes = new TypeSymbol[ps.Length];
                    int p = 0;
                    while (p < ps.Length) {
                        paramTypes[p] = new TypeSymbol(ps[p].Type().DisplayName());
                        p = p + 1;
                    }
                    MethodSignature sig = new MethodSignature(decl.Name(), decl.IsStatic(), returnType, paramTypes);
                    methods = AppendMethod(methods, methodCount, sig);
                    methodNames = AppendString(methodNames, methodCount, decl.Name());
                    methodCount = methodCount + 1;
                }
                i = i + 1;
            }

            return new TypeInfo(cl.Name(), methods);
        }

        private static bool Contains(string[] items, string value) {
            int i = 0;
            while (i < items.Length) {
                if (items[i] == value) { return true; }
                i = i + 1;
            }
            return false;
        }

        private static string[] AppendString(string[] items, int count, string item) {
            string[] next = new string[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private static TypeInfo[] AppendType(TypeInfo[] items, int count, TypeInfo item) {
            TypeInfo[] next = new TypeInfo[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private static MethodSignature[] AppendMethod(MethodSignature[] items, int count, MethodSignature item) {
            MethodSignature[] next = new MethodSignature[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }
    }
}

