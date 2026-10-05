using Hydrogen.Compiler.IR;
using Hydrogen.Compiler.Syntax;

namespace Hydrogen.Compiler.Binding {
    public class ExecutableLowering {
        public IrModule Lower(CompilationUnitSyntax[] units) {
            IrClass[] classes = new IrClass[0];
            IrEnum[] enums = new IrEnum[0];
            int u = 0;
            while (u < units.Length) {
                IrImport[] imports = new IrImport[units[u].Usings().Length];
                int i = 0;
                while (i < imports.Length) { imports[i] = new IrImport(units[u].Usings()[i].Name()); i = i + 1; }
                classes = Classes(classes, units[u].Classes(), "", imports);
                enums = Enums(enums, units[u].Enums(), "");
                IrClass[] interfaces = Interfaces(units[u].Interfaces(), "", imports);
                classes = AppendClasses(classes, interfaces);
                NamespaceDeclarationSyntax[] ns = units[u].Namespaces();
                i = 0;
                while (i < ns.Length) {
                    classes = Classes(classes, ns[i].Classes(), ns[i].Name() + ".", imports);
                    enums = Enums(enums, ns[i].Enums(), ns[i].Name() + ".");
                    classes = AppendClasses(classes, Interfaces(ns[i].Interfaces(), ns[i].Name() + ".", imports));
                    i = i + 1;
                }
                u = u + 1;
            }
            IrModule module = new IrModule(new IrFunction[0]);
            module.SetRoot(new IrUnit(new IrImport[0], new IrNamespace[0], classes, enums, new IrInterface[0]));
            return module;
        }
        private IrClass[] AppendClasses(IrClass[] old, IrClass[] items) {
            IrClass[] result = new IrClass[old.Length + items.Length];
            int i = 0;
            while (i < old.Length) { result[i] = old[i]; i = i + 1; }
            i = 0;
            while (i < items.Length) { result[old.Length + i] = items[i]; i = i + 1; }
            return result;
        }
        private IrClass[] Interfaces(InterfaceDeclarationSyntax[] input, string prefix, IrImport[] imports) {
            IrClass[] result = new IrClass[input.Length];
            int i = 0;
            while (i < input.Length) {
                string fullName = prefix + input[i].Name();
                IrMethod[] methods = Methods(input[i].Methods());
                result[i] = new IrClass(fullName, new IrField[0], methods);
                result[i].SetImports(imports); result[i].SetInterface(true); i = i + 1;
            }
            return result;
        }
        private IrClass[] Classes(IrClass[] old, ClassDeclarationSyntax[] input, string prefix, IrImport[] imports) {
            IrClass[] result = new IrClass[old.Length + input.Length];
            int i = 0;
            while (i < old.Length) { result[i] = old[i]; i = i + 1; }
            i = 0;
            while (i < input.Length) {
                IrField[] fields = new IrField[input[i].Fields().Length];
                int f = 0;
                while (f < fields.Length) {
                    FieldDeclarationSyntax field = input[i].Fields()[f];
                    IrType fieldType = Type(field.Type());
                    IrExpression initializer = Expression(field.Initializer());
                    fields[f] = new IrField(fieldType, field.Name(), field.IsStatic(), initializer);
                    fields[f].SetPrivate(field.IsPrivate()); f = f + 1;
                }
                string fullName = prefix + input[i].Name();
                IrMethod[] methods = Methods(input[i].Methods());
                result[old.Length + i] = new IrClass(fullName, fields, methods);
                result[old.Length + i].SetImports(imports); i = i + 1;
            }
            return result;
        }
        private IrEnum[] Enums(IrEnum[] old, EnumDeclarationSyntax[] input, string prefix) {
            IrEnum[] result = new IrEnum[old.Length + input.Length];
            int i = 0;
            while (i < old.Length) { result[i] = old[i]; i = i + 1; }
            i = 0;
            while (i < input.Length) {
                IrEnumMember[] members = new IrEnumMember[input[i].Members().Length];
                int m = 0;
                while (m < members.Length) { EnumMemberSyntax member = input[i].Members()[m]; members[m] = new IrEnumMember(member.Name(), member.Value(), member.HasExplicitValue()); m = m + 1; }
                result[old.Length + i] = new IrEnum(prefix + input[i].Name(), members); i = i + 1;
            }
            return result;
        }
        private IrMethod[] Methods(MethodDeclarationSyntax[] input) {
            IrMethod[] result = new IrMethod[input.Length];
            int i = 0;
            while (i < input.Length) {
                IrParameter[] parameters = new IrParameter[input[i].Parameters().Length];
                int p = 0;
                while (p < parameters.Length) { parameters[p] = new IrParameter(Type(input[i].Parameters()[p].Type()), input[i].Parameters()[p].Name()); p = p + 1; }
                IrType returnType = Type(input[i].ReturnType());
                IrStatement body = Statement(input[i].Body());
                result[i] = new IrMethod(input[i].Name(), input[i].IsStatic(), input[i].IsVirtual(), input[i].IsOverride(), returnType, parameters, body);
                result[i].SetPrivate(input[i].IsPrivate()); i = i + 1;
            }
            return result;
        }
        private IrType Type(TypeSyntax type) { if (type == null) { return null; } return new IrType(type.DisplayName()); }
        private IrExpression[] Arguments(ExpressionSyntax[] input) {
            IrExpression[] result = new IrExpression[input.Length]; int i = 0;
            while (i < input.Length) { result[i] = Expression(input[i]); i = i + 1; } return result;
        }
        private IrStatement Statement(StatementSyntax s) {
            if (s == null) { return null; }
            int k = s.Kind();
            if (k == StatementSyntax.KindBlock()) {
                IrStatement[] items = new IrStatement[s.Statements().Length]; int i = 0;
                while (i < items.Length) { items[i] = Statement(s.Statements()[i]); i = i + 1; } return IrStatement.Block(items);
            }
            if (k == StatementSyntax.KindIfStatement()) { IrExpression condition = Expression(s.Condition()); IrStatement thenBody = Statement(s.ThenStatement()); IrStatement elseBody = Statement(s.ElseStatement()); return IrStatement.If(condition, thenBody, elseBody); }
            if (k == StatementSyntax.KindReturnStatement()) { return IrStatement.Return(Expression(s.Expression())); }
            if (k == StatementSyntax.KindExpressionStatement()) { return IrStatement.ExpressionStatement(Expression(s.Expression())); }
            if (k == StatementSyntax.KindVariableDeclaration()) { IrType type = Type(s.Type()); IrExpression value = Expression(s.Initializer()); return IrStatement.VariableDeclaration(type, s.Name(), value); }
            if (k == StatementSyntax.KindWhileStatement()) { IrExpression condition = Expression(s.Condition()); IrStatement body = Statement(s.Body()); return IrStatement.While(condition, body); }
            if (k == StatementSyntax.KindBreakStatement()) { return IrStatement.Break(); }
            if (k == StatementSyntax.KindContinueStatement()) { return IrStatement.Continue(); }
            if (k == StatementSyntax.KindTryStatement()) { IrStatement body = Statement(s.Body()); IrType type = Type(s.CatchType()); IrStatement handler = Statement(s.CatchBlock()); return IrStatement.Try(body, type, s.CatchName(), handler); }
            return IrStatement.Throw(Expression(s.Expression()));
        }
        private IrExpression Expression(ExpressionSyntax e) {
            if (e == null) { return null; }
            int k = e.Kind();
            if (k == ExpressionSyntax.KindName()) { return IrExpression.NameExpr(e.Name()); }
            if (k == ExpressionSyntax.KindLiteral()) { return IrExpression.Literal(e.LiteralKind(), e.LiteralText()); }
            if (k == ExpressionSyntax.KindMemberAccess()) { return IrExpression.MemberAccess(Expression(e.Receiver()), e.MemberName()); }
            if (k == ExpressionSyntax.KindInvocation()) { IrExpression target = Expression(e.Target()); IrExpression[] arguments = Arguments(e.Arguments()); return IrExpression.Invocation(target, arguments); }
            if (k == ExpressionSyntax.KindAssignment()) { IrExpression target = Expression(e.Target()); IrExpression value = Expression(e.Value()); return IrExpression.Assignment(target, value); }
            if (k == ExpressionSyntax.KindBinary()) { IrExpression left = Expression(e.Left()); IrExpression right = Expression(e.Right()); return IrExpression.Binary(left, (int)e.OperatorKind(), right); }
            if (k == ExpressionSyntax.KindIndex()) { IrExpression receiver = Expression(e.Receiver()); IrExpression index = Expression(e.Index()); return IrExpression.IndexExpr(receiver, index); }
            if (k == ExpressionSyntax.KindObjectCreation()) { IrType type = Type(e.Type()); IrExpression[] arguments = Arguments(e.Arguments()); return IrExpression.ObjectCreation(type, arguments); }
            if (k == ExpressionSyntax.KindArrayCreation()) { IrType type = Type(e.Type()); IrExpression size = Expression(e.Size()); return IrExpression.ArrayCreation(type, size); }
            if (k == ExpressionSyntax.KindCast()) { IrType type = Type(e.CastType()); IrExpression value = Expression(e.CastExpression()); return IrExpression.Cast(type, value); }
            if (k == ExpressionSyntax.KindUnary()) { return IrExpression.Unary((int)e.UnaryOperatorKind(), Expression(e.UnaryOperand())); }
            return IrExpression.SizeOf(Type(e.SizeOfType()));
        }
    }
}
