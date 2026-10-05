using Hydrogen.Compiler.Diagnostics;
using Hydrogen.Compiler.IR;
using Hydrogen.Compiler.Syntax;

namespace Hydrogen.Compiler.Binding {
    public class Binder {
        public BoundProgram Bind(CompilationUnitSyntax root, DiagnosticBag diagnostics) {
            CompilationUnitSyntax[] units = new CompilationUnitSyntax[1]; units[0] = root;
            return BindUnits(units, diagnostics);
        }
        public BoundProgram BindUnits(CompilationUnitSyntax[] units, DiagnosticBag diagnostics) {
            ExecutableLowering lowering = new ExecutableLowering();
            IrModule module = lowering.Lower(units);
            ExecutableChecker checker = new ExecutableChecker(); checker.Check(module, diagnostics);
            MethodSymbol[] methods = new MethodSymbol[0];
            IrClass[] classes = module.Root().Classes(); int c = 0;
            while (c < classes.Length) {
                IrMethod[] declarations = classes[c].Methods(); int m = 0;
                while (m < declarations.Length) {
                    IrParameter[] parameters = declarations[m].Parameters();
                    ParameterSymbol[] ps = new ParameterSymbol[parameters.Length]; int p = 0;
                    while (p < parameters.Length) { ps[p] = new ParameterSymbol(parameters[p].Name(), new TypeSymbol(parameters[p].Type().DisplayName())); p = p + 1; }
                    MethodSymbol[] next = new MethodSymbol[methods.Length + 1]; p = 0;
                    while (p < methods.Length) { next[p] = methods[p]; p = p + 1; }
                    next[p] = new MethodSymbol(declarations[m].Name(), declarations[m].IsStatic(), new TypeSymbol(declarations[m].ReturnType().DisplayName()), ps); methods = next; m = m + 1;
                }
                c = c + 1;
            }
            // Preserve the tiny entrypoint debug view for existing clients. Native
            // code generation uses the complete module, never these debug operations.
            BoundOp[] entry = new BoundOp[0]; int u = 0;
            while (u < units.Length) {
                ClassDeclarationSyntax[] cls = units[u].Classes(); c = 0;
                while (c < cls.Length) { BoundOp[] ops = TryBindEntryPointOps(cls[c], diagnostics); if (ops.Length != 0) { entry = ops; } c = c + 1; }
                int n = 0;
                while (n < units[u].Namespaces().Length) {
                    cls = units[u].Namespaces()[n].Classes(); c = 0;
                    while (c < cls.Length) { BoundOp[] ops = TryBindEntryPointOps(cls[c], diagnostics); if (ops.Length != 0) { entry = ops; } c = c + 1; } n = n + 1;
                }
                u = u + 1;
            }
            BoundProgram program = new BoundProgram(methods, entry); program.SetModule(module); return program;
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
            bool supported = true;

            int i = 0;
            while (i < statements.Length) {
                if (statements[i].Kind() == StatementSyntax.KindExpressionStatement()) {
                    BoundOp op = BindExpressionStatement(statements[i], diagnostics);
                    if (op != null) {
                        ops = AppendOp(ops, count, op);
                        count = count + 1;
                    } else {
                        supported = false;
                    }
                } else if (statements[i].Kind() == StatementSyntax.KindReturnStatement()) {
                    sawReturn = true;
                    int code = BindReturnExitCode(statements[i], diagnostics);
                    if (code < 0) {
                        supported = false;
                        exitCode = 0;
                    } else {
                        exitCode = code;
                    }
                } else {
                    supported = false;
                }
                i = i + 1;
            }

            if (method.ReturnType().DisplayName() == "int" && !sawReturn) {
                // default is 0
            }

            if (!supported) {
                return new BoundOp[0];
            }
            ops = AppendOp(ops, count, new BoundOp(BoundOp.KindExit(), "", exitCode));
            return ops;
        }

        private BoundOp BindExpressionStatement(StatementSyntax statement, DiagnosticBag diagnostics) {
            // Only support System.Console.WriteLine("literal");
            ExpressionSyntax expression = statement.Expression();
            if (expression.Kind() != ExpressionSyntax.KindInvocation()) {
                return null;
            }

            ExpressionSyntax target = expression.Target();
            if (!IsSystemConsoleWriteLine(target)) {
                return null;
            }

            ExpressionSyntax[] args = expression.Arguments();
            if (args.Length != 1) {
                return null;
            }
            if (args[0].Kind() != ExpressionSyntax.KindLiteral()) {
                return null;
            }
            if (args[0].LiteralKind() != "string") {
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
                return -1;
            }
            if (statement.Expression().LiteralKind() != "number") {
                return -1;
            }
            return ParseInt(statement.Expression().LiteralText());
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
