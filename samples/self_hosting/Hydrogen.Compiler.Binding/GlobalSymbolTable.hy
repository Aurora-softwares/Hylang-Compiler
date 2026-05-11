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
        private string namespaceName;
        private string name;
        private string fullName;
        private MethodSignature[] methods;

        public TypeInfo(string inputNamespaceName, string inputName, MethodSignature[] inputMethods) {
            namespaceName = inputNamespaceName;
            name = inputName;
            if (namespaceName == "") {
                fullName = name;
            } else {
                fullName = namespaceName + "." + name;
            }
            methods = inputMethods;
        }

        public string NamespaceName() { return namespaceName; }
        public string Name() { return name; }
        public string FullName() { return fullName; }
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

        public TypeInfo TryGetTypeByFullName(string fullTypeName) {
            int i = 0;
            while (i < types.Length) {
                if (types[i].FullName() == fullTypeName) {
                    return types[i];
                }
                i = i + 1;
            }
            return null;
        }

        public MethodSignature TryGetMethodInType(string fullTypeName, string methodName) {
            TypeInfo type = TryGetTypeByFullName(fullTypeName);
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
			UsingDirectiveSyntax[] usings = root.Usings();
			string[] typeFullNames = new string[0];
			TypeInfo[] typeInfos = new TypeInfo[0];
			int typeCount = 0;

			ClassDeclarationSyntax[] topClasses = root.Classes();
			int c = 0;
			while (c < topClasses.Length) {
				string name = topClasses[c].Name();
				string full = name;
				if (Contains(typeFullNames, full)) {
					diagnostics.Report(1, 1, "duplicate type: " + full);
				} else {
					TypeInfo info = BuildTypeInfo("", topClasses[c], usings, diagnostics);
					typeFullNames = AppendString(typeFullNames, typeCount, full);
					typeInfos = AppendType(typeInfos, typeCount, info);
					typeCount = typeCount + 1;
				}
				c = c + 1;
			}

			EnumDeclarationSyntax[] topEnums = root.Enums();
			int e = 0;
			while (e < topEnums.Length) {
				string name = topEnums[e].Name();
				string full = name;
				if (Contains(typeFullNames, full)) {
					diagnostics.Report(1, 1, "duplicate type: " + full);
				} else {
					TypeInfo info = BuildEnumTypeInfo("", topEnums[e]);
					typeFullNames = AppendString(typeFullNames, typeCount, full);
					typeInfos = AppendType(typeInfos, typeCount, info);
					typeCount = typeCount + 1;
				}
				e = e + 1;
			}

			InterfaceDeclarationSyntax[] topInterfaces = root.Interfaces();
			int i = 0;
			while (i < topInterfaces.Length) {
				string name = topInterfaces[i].Name();
				string full = name;
				if (Contains(typeFullNames, full)) {
					diagnostics.Report(1, 1, "duplicate type: " + full);
				} else {
					TypeInfo info = BuildInterfaceTypeInfo("", topInterfaces[i]);
					typeFullNames = AppendString(typeFullNames, typeCount, full);
					typeInfos = AppendType(typeInfos, typeCount, info);
					typeCount = typeCount + 1;
				}
				i = i + 1;
			}

			NamespaceDeclarationSyntax[] namespaces = root.Namespaces();
			int n = 0;
			while (n < namespaces.Length) {
				string nsName = namespaces[n].Name();
				ClassDeclarationSyntax[] classes = namespaces[n].Classes();
				EnumDeclarationSyntax[] enums = namespaces[n].Enums();
				InterfaceDeclarationSyntax[] interfaces = namespaces[n].Interfaces();

				int c2 = 0;
				while (c2 < classes.Length) {
					string name2 = classes[c2].Name();
					string full2 = nsName + "." + name2;
					if (Contains(typeFullNames, full2)) {
						diagnostics.Report(1, 1, "duplicate type: " + full2);
					} else {
						TypeInfo info2 = BuildTypeInfo(nsName, classes[c2], usings, diagnostics);
						typeFullNames = AppendString(typeFullNames, typeCount, full2);
						typeInfos = AppendType(typeInfos, typeCount, info2);
						typeCount = typeCount + 1;
					}
					c2 = c2 + 1;
				}
				int e2 = 0;
				while (e2 < enums.Length) {
					string enumName = enums[e2].Name();
					string enumFull = nsName + "." + enumName;

					if (Contains(typeFullNames, enumFull)) {
						diagnostics.Report(1, 1, "duplicate type: " + enumFull);
					} else {
						TypeInfo enumInfo = BuildEnumTypeInfo(nsName, enums[e2]);
						typeFullNames = AppendString(typeFullNames, typeCount, enumFull);
						typeInfos = AppendType(typeInfos, typeCount, enumInfo);
						typeCount = typeCount + 1;
					}

					e2 = e2 + 1;
				}
				int i2 = 0;
				while (i2 < interfaces.Length) {
					string interfaceName = interfaces[i2].Name();
					string interfaceFull = nsName + "." + interfaceName;

					if (Contains(typeFullNames, interfaceFull)) {
						diagnostics.Report(1, 1, "duplicate type: " + interfaceFull);
					} else {
						TypeInfo interfaceInfo = BuildInterfaceTypeInfo(nsName, interfaces[i2]);
						typeFullNames = AppendString(typeFullNames, typeCount, interfaceFull);
						typeInfos = AppendType(typeInfos, typeCount, interfaceInfo);
						typeCount = typeCount + 1;
					}

					i2 = i2 + 1;
				}
				n = n + 1;
			}

			return new GlobalSymbolTable(typeInfos);
		}

        public TypeInfo TryResolveType(string typeName, string currentNamespaceName, UsingDirectiveSyntax[] usings) {
            string resolved = ResolveTypeName(typeName, currentNamespaceName, usings);
            if (resolved == null) { return null; }
            return TryGetTypeByFullName(resolved);
        }

        public string ResolveTypeName(string typeName, string currentNamespaceName, UsingDirectiveSyntax[] usings) {
            if (typeName == null) { return null; }
            if (typeName == "int" || typeName == "bool" || typeName == "string" || typeName == "void" || typeName == "byte" ||
                typeName == "string[]" || typeName == "byte[]") {
                return typeName;
            }

            if (EndsWith(typeName, "[]")) {
                string elementName = Slice(typeName, 0, typeName.Length - 2);
                string resolvedElement = ResolveTypeName(elementName, currentNamespaceName, usings);
                if (resolvedElement == null) { return null; }
                return resolvedElement + "[]";
            }

            if (ContainsChar(typeName, ".")) {
                if (TryGetTypeByFullName(typeName) != null) { return typeName; }
                return typeName;
            }

            if (currentNamespaceName != null && currentNamespaceName != "") {
                string candidate = currentNamespaceName + "." + typeName;
                if (TryGetTypeByFullName(candidate) != null) { return candidate; }
            }

            if (TryGetTypeByFullName(typeName) != null) { return typeName; }

            string found = "";
            int i = 0;
            while (i < usings.Length) {
                // Defensive: parser should never produce null using entries, but don't let a null
                // propagate into an interpreter crash during self-host validation.
                if (usings[i] != null) {
                    string cand = usings[i].Name() + "." + typeName;
                    if (TryGetTypeByFullName(cand) != null) {
                        if (found == "") {
                            found = cand;
                        } else {
                            // Duplicate `using` lines can repeat the same candidate; only treat it as
                            // ambiguous if it resolves to a different type.
                            if (found != cand) {
                                return null;
                            }
                        }
                    }
                }
                i = i + 1;
            }
            if (found != "") { return found; }

            return typeName;
        }

        private static TypeInfo BuildTypeInfo(string namespaceName, ClassDeclarationSyntax cl, UsingDirectiveSyntax[] usings, DiagnosticBag diagnostics) {
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
                    string resolvedReturn = ResolveTypeNameStatic(decl.ReturnType().DisplayName(), namespaceName, usings);
                    TypeSymbol returnType = new TypeSymbol(resolvedReturn);
                    ParameterSyntax[] ps = decl.Parameters();
                    TypeSymbol[] paramTypes = new TypeSymbol[ps.Length];
                    int p = 0;
                    while (p < ps.Length) {
                        string resolvedParam = ResolveTypeNameStatic(ps[p].Type().DisplayName(), namespaceName, usings);
                        paramTypes[p] = new TypeSymbol(resolvedParam);
                        p = p + 1;
                    }
                    MethodSignature sig = new MethodSignature(decl.Name(), decl.IsStatic(), returnType, paramTypes);
                    methods = AppendMethod(methods, methodCount, sig);
                    methodNames = AppendString(methodNames, methodCount, decl.Name());
                    methodCount = methodCount + 1;
                }
                i = i + 1;
            }

            return new TypeInfo(namespaceName, cl.Name(), methods);
        }

		private static TypeInfo BuildEnumTypeInfo(string namespaceName, EnumDeclarationSyntax en) {
			MethodSignature[] methods = new MethodSignature[0];
			return new TypeInfo(namespaceName, en.Name(), methods);
		}

		private static TypeInfo BuildInterfaceTypeInfo(string namespaceName, InterfaceDeclarationSyntax iface) {
			MethodSignature[] methods = BuildInterfaceMethods(iface.Methods());
			return new TypeInfo(namespaceName, iface.Name(), methods);
		}

        private static bool Contains(string[] items, string value) {
            int i = 0;
            while (i < items.Length) {
                if (items[i] == value) { return true; }
                i = i + 1;
            }
            return false;
        }

        private static bool EndsWith(string text, string suffix) {
            if (text.Length < suffix.Length) { return false; }
            int i = 0;
            while (i < suffix.Length) {
                if (text[text.Length - suffix.Length + i] != suffix[i]) { return false; }
                i = i + 1;
            }
            return true;
        }

        private static bool ContainsChar(string text, string ch) {
            int i = 0;
            while (i < text.Length) {
                if (text[i] == ch) { return true; }
                i = i + 1;
            }
            return false;
        }

        private static string Slice(string text, int start, int length) {
            string result = "";
            int i = 0;
            while (i < length && start + i < text.Length) {
                result = result + text[start + i];
                i = i + 1;
            }
            return result;
        }

        private static string ResolveTypeNameStatic(string typeName, string currentNamespaceName, UsingDirectiveSyntax[] usings) {
            if (typeName == null) { return "unknown"; }
            if (typeName == "int" || typeName == "bool" || typeName == "string" || typeName == "void" || typeName == "byte" ||
                typeName == "string[]" || typeName == "byte[]") {
                return typeName;
            }
            if (EndsWith(typeName, "[]")) {
                string elementName = Slice(typeName, 0, typeName.Length - 2);
                string resolvedElement = ResolveTypeNameStatic(elementName, currentNamespaceName, usings);
                return resolvedElement + "[]";
            }
            if (ContainsChar(typeName, ".")) { return typeName; }
            return typeName;
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

		private static MethodSignature[] BuildInterfaceMethods(MethodDeclarationSyntax[] methods) {
			MethodSignature[] signatures = new MethodSignature[methods.Length];

			int i = 0;
			while (i < methods.Length) {
				ParameterSyntax[] parameters = methods[i].Parameters();
				TypeSymbol[] parameterTypes = new TypeSymbol[parameters.Length];

				int p = 0;
				while (p < parameters.Length) {
					parameterTypes[p] = new TypeSymbol(parameters[p].Type().DisplayName());
					p = p + 1;
				}

				TypeSymbol returnType = new TypeSymbol(methods[i].ReturnType().DisplayName());

				signatures[i] = new MethodSignature(
					methods[i].Name(),
					methods[i].IsStatic(),
					returnType,
					parameterTypes
				);

				i = i + 1;
			}

			return signatures;
		}
    }
}
