using Hydrogen.Compiler.Diagnostics;
using Hydrogen.Compiler.Syntax;

namespace Hydrogen.Compiler.Binding {
    public class Binder {
        public BoundProgram Bind(CompilationUnitSyntax root, DiagnosticBag diagnostics) {
            // Stage1B: build a deterministic symbol table for methods so we can type-check
            // the compiler sources (still a subset; no overload resolution yet).
            string[] methodOwnerTypes = new string[0];
            MethodDeclarationSyntax[] methodDecls = new MethodDeclarationSyntax[0];
            int methodDeclCount = 0;

            MethodSymbol[] methods = new MethodSymbol[0];
            int methodCount = 0;
            BoundOp[] entryOps = new BoundOp[0];

            // Top-level classes
            ClassDeclarationSyntax[] topClasses = root.Classes();
            int i = 0;
            while (i < topClasses.Length) {
                MethodDeclarationSyntax[] decls0 = topClasses[i].Methods();
                int d0 = 0;
                while (d0 < decls0.Length) {
                    methodOwnerTypes = AppendString(methodOwnerTypes, methodDeclCount, topClasses[i].Name());
                    methodDecls = AppendMethodDecl(methodDecls, methodDeclCount, decls0[d0]);
                    methodDeclCount = methodDeclCount + 1;
                    d0 = d0 + 1;
                }

                BoundOp[] ops = TryBindEntryPointOps(topClasses[i], diagnostics);
                if (ops.Length != 0) {
                    entryOps = ops;
                }
                methods = AppendMethods(methods, methodCount, BindClass(topClasses[i], diagnostics));
                methodCount = methods.Length;
                i = i + 1;
            }

            // Namespaces
            NamespaceDeclarationSyntax[] namespaces = root.Namespaces();
            int n = 0;
            while (n < namespaces.Length) {
                ClassDeclarationSyntax[] classes = namespaces[n].Classes();
                int c = 0;
                while (c < classes.Length) {
                    MethodDeclarationSyntax[] decls1 = classes[c].Methods();
                    int d1 = 0;
                    while (d1 < decls1.Length) {
                        methodOwnerTypes = AppendString(methodOwnerTypes, methodDeclCount, classes[c].Name());
                        methodDecls = AppendMethodDecl(methodDecls, methodDeclCount, decls1[d1]);
                        methodDeclCount = methodDeclCount + 1;
                        d1 = d1 + 1;
                    }

                    BoundOp[] ops = TryBindEntryPointOps(classes[c], diagnostics);
                    if (ops.Length != 0) {
                        entryOps = ops;
                    }
                    methods = AppendMethods(methods, methodCount, BindClass(classes[c], diagnostics));
                    methodCount = methods.Length;
                    c = c + 1;
                }
                n = n + 1;
            }

            // Stage1B binder should be able to bind non-entrypoint code (compiler libraries).
            // Missing/unsupported entrypoint becomes an error only when lowering to native output.

            // Second pass: validate method bodies using the method symbol table.
            int v = 0;
            while (v < methodDeclCount) {
                ValidateMethodBody(methodDecls[v], methodOwnerTypes[v], methodOwnerTypes, methodDecls, methodDeclCount, diagnostics);
                v = v + 1;
            }
            return new BoundProgram(methods, entryOps);
        }

        private MethodSymbol[] BindClass(ClassDeclarationSyntax cl, DiagnosticBag diagnostics) {
            MethodDeclarationSyntax[] decls = cl.Methods();
            MethodSymbol[] methods = new MethodSymbol[decls.Length];
            int i = 0;
            while (i < decls.Length) {
                methods[i] = BindMethod(decls[i], diagnostics);
                i = i + 1;
            }
            return methods;
        }

        private MethodSymbol BindMethod(MethodDeclarationSyntax method, DiagnosticBag diagnostics) {
            TypeSymbol returnType = ResolveType(method.ReturnType(), diagnostics);
            ParameterSyntax[] parameters = method.Parameters();
            ParameterSymbol[] boundParameters = new ParameterSymbol[parameters.Length];
            int i = 0;
            while (i < parameters.Length) {
                boundParameters[i] = new ParameterSymbol(parameters[i].Name(), ResolveType(parameters[i].Type(), diagnostics));
                i = i + 1;
            }
            return new MethodSymbol(method.Name(), method.IsStatic(), returnType, boundParameters);
        }

        private BoundOp[] TryBindEntryPointOps(ClassDeclarationSyntax cl, DiagnosticBag diagnostics) {
            MethodDeclarationSyntax[] decls = cl.Methods();
            int i = 0;
            while (i < decls.Length) {
                MethodDeclarationSyntax method = decls[i];
                if (IsSupportedMain(method)) {
                    return BindMainBody(method, diagnostics);
                }
                i = i + 1;
            }
            return new BoundOp[0];
        }

        private bool IsSupportedMain(MethodDeclarationSyntax method) {
            if (!method.IsStatic()) {
                return false;
            }
            if (method.Name() != "Main") {
                return false;
            }
            ParameterSyntax[] parameters = method.Parameters();
            if (parameters.Length != 1) {
                return false;
            }
            if (parameters[0].Type().DisplayName() != "string[]") {
                return false;
            }
            string returnType = method.ReturnType().DisplayName();
            return returnType == "void" || returnType == "int";
        }

        private BoundOp[] BindMainBody(MethodDeclarationSyntax method, DiagnosticBag diagnostics) {
            StatementSyntax[] statements = method.Body().Statements();
            BoundOp[] ops = new BoundOp[0];
            int count = 0;
            int exitCode = 0;
            bool sawReturn = false;

            int i = 0;
            while (i < statements.Length) {
                if (statements[i].Kind() == StatementSyntax.KindExpressionStatement()) {
                    BoundOp op = BindExpressionStatement(statements[i], diagnostics);
                    if (op != null) {
                        ops = AppendOp(ops, count, op);
                        count = count + 1;
                    }
                } else if (statements[i].Kind() == StatementSyntax.KindReturnStatement()) {
                    sawReturn = true;
                    exitCode = BindReturnExitCode(statements[i], diagnostics);
                } else {
                    diagnostics.Report(1, 1, "unsupported statement in entry point");
                }
                i = i + 1;
            }

            if (method.ReturnType().DisplayName() == "int" && !sawReturn) {
                // default is 0
            }

            ops = AppendOp(ops, count, new BoundOp(BoundOp.KindExit(), "", exitCode));
            return ops;
        }

        private BoundOp BindExpressionStatement(StatementSyntax statement, DiagnosticBag diagnostics) {
            // Only support System.Console.WriteLine("literal");
            ExpressionSyntax expression = statement.Expression();
            if (expression.Kind() != ExpressionSyntax.KindInvocation()) {
                diagnostics.Report(1, 1, "unsupported expression statement in entry point");
                return null;
            }

            ExpressionSyntax target = expression.Target();
            if (!IsSystemConsoleWriteLine(target)) {
                diagnostics.Report(1, 1, "only System.Console.WriteLine is supported in entry point");
                return null;
            }

            ExpressionSyntax[] args = expression.Arguments();
            if (args.Length != 1) {
                diagnostics.Report(1, 1, "WriteLine requires exactly one argument in this phase");
                return null;
            }
            if (args[0].Kind() != ExpressionSyntax.KindLiteral()) {
                diagnostics.Report(1, 1, "WriteLine argument must be a literal in this phase");
                return null;
            }
            if (args[0].LiteralKind() != "string") {
                diagnostics.Report(1, 1, "WriteLine argument must be a string literal in this phase");
                return null;
            }

            // Lexer gives us raw string token text without quotes.
            return new BoundOp(BoundOp.KindWriteLineLiteral(), args[0].LiteralText(), 0);
        }

        private bool IsSystemConsoleWriteLine(ExpressionSyntax target) {
            // Parse member chain: ((System).Console).WriteLine
            if (target.Kind() != ExpressionSyntax.KindMemberAccess()) {
                return false;
            }
            if (target.MemberName() != "WriteLine") {
                return false;
            }
            ExpressionSyntax receiver = target.Receiver();
            if (receiver.Kind() != ExpressionSyntax.KindMemberAccess()) {
                return false;
            }
            if (receiver.MemberName() != "Console") {
                return false;
            }
            ExpressionSyntax systemExpr = receiver.Receiver();
            if (systemExpr.Kind() != ExpressionSyntax.KindName()) {
                return false;
            }
            return systemExpr.Name() == "System";
        }

        private int BindReturnExitCode(StatementSyntax statement, DiagnosticBag diagnostics) {
            if (statement.Expression() == null) {
                return 0;
            }
            if (statement.Expression().Kind() != ExpressionSyntax.KindLiteral()) {
                diagnostics.Report(1, 1, "return expression must be a literal in this phase");
                return 0;
            }
            if (statement.Expression().LiteralKind() != "number") {
                diagnostics.Report(1, 1, "return expression must be an integer literal in this phase");
                return 0;
            }
            return ParseInt(statement.Expression().LiteralText());
        }

        private void ValidateMethodBody(MethodDeclarationSyntax method, string ownerTypeName, string[] methodOwnerTypes, MethodDeclarationSyntax[] methodDecls, int methodDeclCount, DiagnosticBag diagnostics) {
            ParameterSyntax[] parameters = method.Parameters();
            string[] localNames = new string[0];
            TypeSymbol[] localTypes = new TypeSymbol[0];
            int localCount = 0;
            ValidateStatement(method.Body(), method.ReturnType(), ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
        }

        private void ValidateStatement(StatementSyntax statement, TypeSyntax returnType, string ownerTypeName, string[] methodOwnerTypes, MethodDeclarationSyntax[] methodDecls, int methodDeclCount, ParameterSyntax[] parameters, string[] localNames, TypeSymbol[] localTypes, int localCount, DiagnosticBag diagnostics) {
            if (statement == null) { return; }

            int kind = statement.Kind();
            if (kind == StatementSyntax.KindBlock()) {
                StatementSyntax[] items = statement.Statements();
                int i = 0;
                while (i < items.Length) {
                    ValidateStatement(items[i], returnType, ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                    i = i + 1;
                }
                return;
            }
            if (kind == StatementSyntax.KindIfStatement()) {
                TypeSymbol conditionType = ValidateExpression(statement.Condition(), ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                if (conditionType != null && conditionType.Name() != "bool" && conditionType.Name() != "unknown") {
                    diagnostics.Report(1, 1, "if condition must be bool");
                }
                ValidateStatement(statement.ThenStatement(), returnType, ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                if (statement.ElseStatement() != null) {
                    ValidateStatement(statement.ElseStatement(), returnType, ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                }
                return;
            }
            if (kind == StatementSyntax.KindWhileStatement()) {
                TypeSymbol whileConditionType = ValidateExpression(statement.Condition(), ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                if (whileConditionType != null && whileConditionType.Name() != "bool" && whileConditionType.Name() != "unknown") {
                    diagnostics.Report(1, 1, "while condition must be bool");
                }
                ValidateStatement(statement.Body(), returnType, ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                return;
            }
            if (kind == StatementSyntax.KindReturnStatement()) {
                if (statement.Expression() == null) {
                    if (returnType.DisplayName() != "void") {
                        diagnostics.Report(1, 1, "return value required");
                    }
                    return;
                }
                TypeSymbol valueType = ValidateExpression(statement.Expression(), ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                if (valueType != null && valueType.Name() != "unknown") {
                    TypeSymbol expected = ResolveType(returnType, diagnostics);
                    if (!TypesEqual(valueType, expected) && !(expected.Name() != "void" && valueType.Name() == "null")) {
                        diagnostics.Report(1, 1, "return type mismatch");
                    }
                }
                return;
            }
            if (kind == StatementSyntax.KindVariableDeclaration()) {
                TypeSymbol declared = ResolveType(statement.Type(), diagnostics);
                localNames = AppendLocalName(localNames, localCount, statement.Name());
                localTypes = AppendLocalType(localTypes, localCount, declared);
                localCount = localCount + 1;
                if (statement.Initializer() != null) {
                    TypeSymbol initType = ValidateExpression(statement.Initializer(), ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                    if (initType != null && initType.Name() != "unknown" && !TypesEqual(initType, declared)) {
                        diagnostics.Report(1, 1, "cannot assign '" + initType.Name() + "' to '" + declared.Name() + "'");
                    }
                }
                return;
            }
            if (kind == StatementSyntax.KindExpressionStatement()) {
                ValidateExpression(statement.Expression(), ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                return;
            }
        }

        private TypeSymbol ValidateExpression(ExpressionSyntax expression, string ownerTypeName, string[] methodOwnerTypes, MethodDeclarationSyntax[] methodDecls, int methodDeclCount, ParameterSyntax[] parameters, string[] localNames, TypeSymbol[] localTypes, int localCount, DiagnosticBag diagnostics) {
            if (expression == null) { return null; }

            int kind = expression.Kind();
            if (kind == ExpressionSyntax.KindLiteral()) {
                if (expression.LiteralKind() == "string") { return new TypeSymbol("string"); }
                if (expression.LiteralKind() == "number") { return new TypeSymbol("int"); }
                if (expression.LiteralKind() == "bool") { return new TypeSymbol("bool"); }
                if (expression.LiteralKind() == "null") { return new TypeSymbol("null"); }
                return new TypeSymbol("unknown");
            }
            if (kind == ExpressionSyntax.KindName()) {
                TypeSymbol local = LookupLocal(expression.Name(), parameters, localNames, localTypes, localCount, diagnostics);
                if (local != null) { return local; }
                return new TypeSymbol("unknown");
            }
            if (kind == ExpressionSyntax.KindMemberAccess()) {
                TypeSymbol receiverType = ValidateExpression(expression.Receiver(), ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                if (expression.MemberName() == "Length" && receiverType != null) {
                    if (receiverType.Name() == "string" || IsArrayType(receiverType)) {
                        return new TypeSymbol("int");
                    }
                }
                return new TypeSymbol("unknown");
            }
            if (kind == ExpressionSyntax.KindIndex()) {
                TypeSymbol receiverType2 = ValidateExpression(expression.Receiver(), ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                TypeSymbol indexType = ValidateExpression(expression.Index(), ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                if (indexType != null && indexType.Name() != "int" && indexType.Name() != "unknown") {
                    diagnostics.Report(1, 1, "index must be int");
                }
                if (receiverType2 != null) {
                    if (receiverType2.Name() == "string") { return new TypeSymbol("string"); }
                    if (IsArrayType(receiverType2)) { return ElementTypeOf(receiverType2); }
                }
                return new TypeSymbol("unknown");
            }
            if (kind == ExpressionSyntax.KindInvocation()) {
                ExpressionSyntax[] args = expression.Arguments();
                int a = 0;
                while (a < args.Length) {
                    ValidateExpression(args[a], ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                    a = a + 1;
                }

                // User-defined calls (no overloads yet):
                MethodDeclarationSyntax callee = ResolveCallee(expression.Target(), ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount);
                if (callee != null) {
                    // Validate argument count/types where known.
                    ParameterSyntax[] ps = callee.Parameters();
                    if (ps.Length != args.Length) {
                        diagnostics.Report(1, 1, "wrong argument count calling '" + callee.Name() + "'");
                        return ResolveType(callee.ReturnType(), diagnostics);
                    }
                    int pi = 0;
                    while (pi < ps.Length) {
                        TypeSymbol expected = ResolveType(ps[pi].Type(), diagnostics);
                        TypeSymbol actual = ValidateExpression(args[pi], ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                        if (actual != null && actual.Name() != "unknown" && expected != null && expected.Name() != "unknown") {
                            if (!TypesEqual(actual, expected)) {
                                diagnostics.Report(1, 1, "argument type mismatch calling '" + callee.Name() + "'");
                            }
                        }
                        pi = pi + 1;
                    }
                    return ResolveType(callee.ReturnType(), diagnostics);
                }

                if (IsSystemConsoleMethod(expression.Target(), "Write") || IsSystemConsoleMethod(expression.Target(), "WriteLine")) {
                    return new TypeSymbol("void");
                }
                if (IsSystemIoFileMethod(expression.Target(), "Exists")) { return new TypeSymbol("bool"); }
                if (IsSystemIoFileMethod(expression.Target(), "ReadAllText")) { return new TypeSymbol("string"); }
                if (IsSystemIoFileMethod(expression.Target(), "WriteAllBytes")) { return new TypeSymbol("void"); }
                if (IsSystemIoFileMethod(expression.Target(), "WriteAllText")) { return new TypeSymbol("void"); }
                if (IsKnownStaticMethod(expression.Target(), "SourceText", "FromFile")) { return new TypeSymbol("SourceText"); }
                if (IsKnownStaticMethod(expression.Target(), "SyntaxTree", "Parse")) { return new TypeSymbol("SyntaxTree"); }
                if (IsKnownStaticMethod(expression.Target(), "HyprojManifest", "Load")) { return new TypeSymbol("HyprojManifest"); }
                if (IsKnownStaticMethod(expression.Target(), "ProjectClosure", "Collect")) { return new TypeSymbol("ProjectClosure"); }
                return new TypeSymbol("unknown");
            }
            if (kind == ExpressionSyntax.KindAssignment()) {
                TypeSymbol right = ValidateExpression(expression.Value(), ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                TypeSymbol left = ValidateExpression(expression.Target(), ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                if (left != null && right != null && left.Name() != "unknown" && right.Name() != "unknown") {
                    if (!TypesEqual(left, right)) {
                        diagnostics.Report(1, 1, "cannot assign '" + right.Name() + "' to '" + left.Name() + "'");
                    }
                }
                return right;
            }
            if (kind == ExpressionSyntax.KindBinary()) {
                TypeSymbol leftT = ValidateExpression(expression.Left(), ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                TypeSymbol rightT = ValidateExpression(expression.Right(), ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                SyntaxKind op = expression.OperatorKind();

                if (op == SyntaxKind.PlusToken) {
                    if (leftT != null && rightT != null) {
                        if (leftT.Name() == "string" && rightT.Name() == "string") { return new TypeSymbol("string"); }
                        if (leftT.Name() == "int" && rightT.Name() == "int") { return new TypeSymbol("int"); }
                    }
                    return new TypeSymbol("unknown");
                }
                if (op == SyntaxKind.MinusToken || op == SyntaxKind.StarToken || op == SyntaxKind.SlashToken || op == SyntaxKind.PercentToken) {
                    return new TypeSymbol("int");
                }
                if (op == SyntaxKind.AmpersandAmpersandToken || op == SyntaxKind.PipePipeToken) {
                    return new TypeSymbol("bool");
                }
                if (op == SyntaxKind.LessToken || op == SyntaxKind.LessEqualsToken || op == SyntaxKind.GreaterToken || op == SyntaxKind.GreaterEqualsToken ||
                    op == SyntaxKind.EqualsEqualsToken || op == SyntaxKind.BangEqualsToken) {
                    return new TypeSymbol("bool");
                }
                return new TypeSymbol("unknown");
            }
            if (kind == ExpressionSyntax.KindObjectCreation()) {
                return new TypeSymbol(expression.Type().DisplayName());
            }
            if (kind == ExpressionSyntax.KindArrayCreation()) {
                TypeSymbol sizeType = ValidateExpression(expression.Size(), ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                if (sizeType != null && sizeType.Name() != "int" && sizeType.Name() != "unknown") {
                    diagnostics.Report(1, 1, "array size must be int");
                }
                return new TypeSymbol(expression.Type().DisplayName() + "[]");
            }
            if (kind == ExpressionSyntax.KindCast()) {
                ValidateExpression(expression.CastExpression(), ownerTypeName, methodOwnerTypes, methodDecls, methodDeclCount, parameters, localNames, localTypes, localCount, diagnostics);
                return new TypeSymbol(expression.CastType().DisplayName());
            }

            return new TypeSymbol("unknown");
        }

        private TypeSymbol LookupLocal(string name, ParameterSyntax[] parameters, string[] localNames, TypeSymbol[] localTypes, int localCount, DiagnosticBag diagnostics) {
            int i = 0;
            while (i < localCount) {
                if (localNames[i] == name) {
                    return localTypes[i];
                }
                i = i + 1;
            }
            int p = 0;
            while (p < parameters.Length) {
                if (parameters[p].Name() == name) {
                    return ResolveType(parameters[p].Type(), diagnostics);
                }
                p = p + 1;
            }
            return null;
        }

        private MethodDeclarationSyntax ResolveCallee(ExpressionSyntax target, string ownerTypeName, string[] methodOwnerTypes, MethodDeclarationSyntax[] methodDecls, int methodDeclCount) {
            if (target == null) { return null; }
            // Unqualified call: prefer same type, then any match.
            if (target.Kind() == ExpressionSyntax.KindName()) {
                MethodDeclarationSyntax inOwner = FindMethodInType(ownerTypeName, target.Name(), methodOwnerTypes, methodDecls, methodDeclCount);
                if (inOwner != null) { return inOwner; }
                return FindFirstMethodByName(target.Name(), methodDecls, methodDeclCount);
            }
            // Static call: TypeName.Method(...)
            if (target.Kind() == ExpressionSyntax.KindMemberAccess() && target.Receiver().Kind() == ExpressionSyntax.KindName()) {
                string typeName = target.Receiver().Name();
                return FindMethodInType(typeName, target.MemberName(), methodOwnerTypes, methodDecls, methodDeclCount);
            }
            return null;
        }

        private MethodDeclarationSyntax FindMethodInType(string typeName, string methodName, string[] methodOwnerTypes, MethodDeclarationSyntax[] methodDecls, int methodDeclCount) {
            int i = 0;
            while (i < methodDeclCount) {
                if (methodOwnerTypes[i] == typeName && methodDecls[i].Name() == methodName) {
                    return methodDecls[i];
                }
                i = i + 1;
            }
            return null;
        }

        private MethodDeclarationSyntax FindFirstMethodByName(string methodName, MethodDeclarationSyntax[] methodDecls, int methodDeclCount) {
            int i = 0;
            while (i < methodDeclCount) {
                if (methodDecls[i].Name() == methodName) {
                    return methodDecls[i];
                }
                i = i + 1;
            }
            return null;
        }

        private bool IsKnownStaticMethod(ExpressionSyntax target, string typeName, string methodName) {
            if (target == null) { return false; }
            if (target.Kind() != ExpressionSyntax.KindMemberAccess()) { return false; }
            if (target.MemberName() != methodName) { return false; }
            if (target.Receiver() == null) { return false; }
            if (target.Receiver().Kind() != ExpressionSyntax.KindName()) { return false; }
            return target.Receiver().Name() == typeName;
        }

        private bool TypesEqual(TypeSymbol left, TypeSymbol right) {
            return left != null && right != null && left.Name() == right.Name();
        }

        private bool IsArrayType(TypeSymbol type) {
            string name = type.Name();
            return name.Length >= 2 && name[name.Length - 2] == "[" && name[name.Length - 1] == "]";
        }

        private TypeSymbol ElementTypeOf(TypeSymbol arrayType) {
            string name = arrayType.Name();
            if (!IsArrayType(arrayType)) { return new TypeSymbol("unknown"); }
            return new TypeSymbol(Slice(name, 0, name.Length - 2));
        }

        private string Slice(string text, int start, int length) {
            string result = "";
            int i = 0;
            while (i < length && start + i < text.Length) {
                result = result + text[start + i];
                i = i + 1;
            }
            return result;
        }

        private string[] AppendLocalName(string[] items, int count, string item) {
            string[] next = new string[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private TypeSymbol[] AppendLocalType(TypeSymbol[] items, int count, TypeSymbol item) {
            TypeSymbol[] next = new TypeSymbol[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private string[] AppendString(string[] items, int count, string item) {
            string[] next = new string[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private MethodDeclarationSyntax[] AppendMethodDecl(MethodDeclarationSyntax[] items, int count, MethodDeclarationSyntax item) {
            MethodDeclarationSyntax[] next = new MethodDeclarationSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private bool IsSystemConsoleMethod(ExpressionSyntax target, string methodName) {
            if (target.Kind() != ExpressionSyntax.KindMemberAccess()) { return false; }
            if (target.MemberName() != methodName) { return false; }
            ExpressionSyntax receiver = target.Receiver();
            if (receiver.Kind() != ExpressionSyntax.KindMemberAccess()) { return false; }
            if (receiver.MemberName() != "Console") { return false; }
            ExpressionSyntax systemExpr = receiver.Receiver();
            if (systemExpr.Kind() != ExpressionSyntax.KindName()) { return false; }
            return systemExpr.Name() == "System";
        }

        private bool IsSystemIoFileMethod(ExpressionSyntax target, string methodName) {
            if (target.Kind() != ExpressionSyntax.KindMemberAccess()) { return false; }
            if (target.MemberName() != methodName) { return false; }
            ExpressionSyntax receiver = target.Receiver();
            if (receiver.Kind() != ExpressionSyntax.KindMemberAccess()) { return false; }
            if (receiver.MemberName() != "File") { return false; }
            ExpressionSyntax ioExpr = receiver.Receiver();
            if (ioExpr.Kind() != ExpressionSyntax.KindMemberAccess()) { return false; }
            if (ioExpr.MemberName() != "IO") { return false; }
            ExpressionSyntax systemExpr = ioExpr.Receiver();
            if (systemExpr.Kind() != ExpressionSyntax.KindName()) { return false; }
            return systemExpr.Name() == "System";
        }

        private int ParseInt(string text) {
            int value = 0;
            int i = 0;
            while (i < text.Length) {
                string ch = text[i];
                if (ch == "0") { value = value * 10 + 0; }
                else if (ch == "1") { value = value * 10 + 1; }
                else if (ch == "2") { value = value * 10 + 2; }
                else if (ch == "3") { value = value * 10 + 3; }
                else if (ch == "4") { value = value * 10 + 4; }
                else if (ch == "5") { value = value * 10 + 5; }
                else if (ch == "6") { value = value * 10 + 6; }
                else if (ch == "7") { value = value * 10 + 7; }
                else if (ch == "8") { value = value * 10 + 8; }
                else if (ch == "9") { value = value * 10 + 9; }
                i = i + 1;
            }
            return value;
        }

        private TypeSymbol ResolveType(TypeSyntax type, DiagnosticBag diagnostics) {
            string name = type.DisplayName();
            if (name == "int" || name == "bool" || name == "string" || name == "void" || name == "byte" ||
                name == "string[]" || name == "byte[]") {
                return new TypeSymbol(name);
            }
            return new TypeSymbol(name);
        }

        private MethodSymbol[] AppendMethods(MethodSymbol[] existing, int count, MethodSymbol[] extra) {
            if (extra.Length == 0) {
                return existing;
            }
            MethodSymbol[] next = new MethodSymbol[count + extra.Length];
            int i = 0;
            while (i < count) {
                next[i] = existing[i];
                i = i + 1;
            }
            int j = 0;
            while (j < extra.Length) {
                next[count + j] = extra[j];
                j = j + 1;
            }
            return next;
        }

        private BoundOp[] AppendOp(BoundOp[] existing, int count, BoundOp op) {
            BoundOp[] next = new BoundOp[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = existing[i];
                i = i + 1;
            }
            next[count] = op;
            return next;
        }
    }
}
