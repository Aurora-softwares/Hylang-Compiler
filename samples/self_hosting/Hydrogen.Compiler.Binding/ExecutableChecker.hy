using Hydrogen.Compiler.Diagnostics;
using Hydrogen.Compiler.IR;

namespace Hydrogen.Compiler.Binding {
    // Declaration pass precedes body checking, so forward and recursive calls have
    // canonical signatures. No file-count heuristic or unresolved-call success path.
    public class ExecutableChecker {
        private IrModule module;
        private DiagnosticBag diagnostics;
        private string owner;
        private IrMethod method;
        private string[] names;
        private string[] types;
        private int count;
        private int scope;
        private int loops;
        public void Check(IrModule input, DiagnosticBag bag) {
            module = input; diagnostics = bag;
            IrClass[] classes = module.Root().Classes(); int c = 0;
            while (c < classes.Length) {
                owner = classes[c].Name();
                int previous = 0;
                while (previous < c) { if (classes[previous].Name() == owner) { Error("duplicate type: " + owner); } previous = previous + 1; }
                if (module.FindEnum(owner) != null) { Error("duplicate type: " + owner); }
                IrField[] fields = classes[c].Fields(); int f = 0;
                while (f < fields.Length) {
                    DeclareType(fields[f].Type(), false); int p = 0;
                    while (p < f) { if (fields[p].Name() == fields[f].Name()) { Error("duplicate field: " + owner + "." + fields[f].Name()); } p = p + 1; } f = f + 1;
                }
                IrMethod[] methods = classes[c].Methods(); int m = 0;
                while (m < methods.Length) {
                    DeclareType(methods[m].ReturnType(), true); int p = 0;
                    while (p < m) { if (methods[p].Name() == methods[m].Name()) { Error("duplicate method in type '" + owner + "': " + methods[m].Name()); } p = p + 1; }
                    p = 0;
                    while (p < methods[m].Parameters().Length) { DeclareType(methods[m].Parameters()[p].Type(), false); p = p + 1; }
                    m = m + 1;
                }
                c = c + 1;
            }
            IrEnum[] enums = module.Root().Enums(); int e = 0;
            while (e < enums.Length) {
                owner = enums[e].Name(); int p = 0;
                while (p < e) { if (enums[p].Name() == owner) { Error("duplicate type: " + owner); } p = p + 1; }
                p = 0;
                while (p < enums[e].Members().Length) {
                    int q = 0;
                    while (q < p) { if (enums[e].Members()[q].Name() == enums[e].Members()[p].Name()) { Error("duplicate enum member: " + enums[e].Members()[p].Name()); } q = q + 1; } p = p + 1;
                }
                e = e + 1;
            }
            if (diagnostics.HasErrors()) { return; }
            c = 0;
            IrFunction[] functions = new IrFunction[0];
            while (c < classes.Length) {
                owner = classes[c].Name();
                IrField[] fields = classes[c].Fields(); int f = 0;
                while (f < fields.Length) {
                    Reset(); string initializerName = "<initializer>"; IrType initializerType = new IrType("void"); IrParameter[] initializerParameters = new IrParameter[0];
                    method = new IrMethod(initializerName, fields[f].IsStatic(), false, false, initializerType, initializerParameters, null);
                    if (fields[f].Initializer() != null) { string actual = Expression(fields[f].Initializer()); Require(actual, fields[f].Type().DisplayName(), "field initializer type mismatch"); } f = f + 1;
                }
                IrMethod[] methods = classes[c].Methods(); int m = 0;
                while (m < methods.Length) {
                    method = methods[m]; Reset();
                    IrParameter[] parameters = method.Parameters(); int p = 0;
                    while (p < parameters.Length) { Add(parameters[p].Name(), parameters[p].Type().DisplayName()); p = p + 1; }
                    Statement(method.Body());
                    if (method.Body() != null && method.ReturnType().DisplayName() != "void") {
                        if (!Returns(method.Body())) { Error("not all paths return a value in " + owner + "." + method.Name()); }
                    }
                    string[] signature = new string[parameters.Length]; p = 0;
                    while (p < parameters.Length) { signature[p] = parameters[p].Type().DisplayName(); p = p + 1; }
                    IrFunction function = new IrFunction(owner + "." + method.Name(), method.ReturnType().DisplayName(), signature); function.SetDeclaration(method);
                    IrFunction[] next = new IrFunction[functions.Length + 1]; p = 0;
                    while (p < functions.Length) { next[p] = functions[p]; p = p + 1; } next[p] = function; functions = next;
                    m = m + 1;
                }
                c = c + 1;
            }
            module.SetFunctions(functions);
        }
        private void Reset() { names = new string[0]; types = new string[0]; count = 0; scope = 0; loops = 0; }
        private void Error(string text) { diagnostics.Report(1, 1, text); }
        private void DeclareType(IrType type, bool allowVoid) {
            string name = type.DisplayName(); string resolved = module.ResolveType(name, owner);
            if (resolved == "<unknown>") { Error("unknown type '" + name + "' in " + owner); }
            else if (resolved == "<ambiguous>") { Error("ambiguous type '" + name + "' in " + owner); }
            else if (resolved == "var" || resolved == "null" || (!allowVoid && resolved == "void") || resolved == "void[]") { Error("invalid declared type '" + name + "'"); }
            type.SetName(resolved);
        }
        private int Local(string name) { int i = count - 1; while (i >= 0) { if (names[i] == name) { return i; } i = i - 1; } return -1; }
        private void Add(string name, string type) {
            int i = scope; while (i < count) { if (names[i] == name) { Error("duplicate local or parameter '" + name + "'"); return; } i = i + 1; }
            string[] n = new string[count + 1]; string[] t = new string[count + 1]; i = 0;
            while (i < count) { n[i] = names[i]; t[i] = types[i]; i = i + 1; } n[count] = name; t[count] = type; names = n; types = t; count = count + 1;
        }
        private bool Assignable(string actual, string expected) {
            if (actual == "<error>" || expected == "<error>") { return true; }
            if (actual == expected && actual != "void") { return true; }
            if (actual == "null" && module.Reference(expected)) { return true; }
            return module.Numeric(actual) && module.Numeric(expected);
        }
        // Evaluate recursive checks before passing literal arguments to Require:
        // the C seed runtime roots locals/parameters, not sibling argument temporaries.
        private void Require(string actual, string expected, string text) { if (!Assignable(actual, expected)) { Error(text); } }
        private void Scoped(IrStatement s) { int saved = count; int savedScope = scope; scope = count; Statement(s); count = saved; scope = savedScope; }
        private void Statement(IrStatement s) {
            if (s == null) { return; }
            int k = s.Kind();
            if (k == IrStatement.KindBlock()) {
                int saved = count; int savedScope = scope; scope = count; int i = 0;
                while (i < s.Statements().Length) { Statement(s.Statements()[i]); i = i + 1; } count = saved; scope = savedScope; return;
            }
            if (k == IrStatement.KindVariableDeclaration()) {
                string type = s.Type().DisplayName(); string value = "";
                if (s.Initializer() != null) { value = Expression(s.Initializer()); }
                if (type == "var") {
                    if (value == "" || value == "void" || value == "null") { Error("var requires a value with a concrete type"); type = "<error>"; } else { type = value; }
                    s.Type().SetName(type);
                } else { DeclareType(s.Type(), false); type = s.Type().DisplayName(); if (value != "") { Require(value, type, "local initializer type mismatch"); } }
                Add(s.Name(), type); return;
            }
            if (k == IrStatement.KindReturnStatement()) {
                string expected = method.ReturnType().DisplayName();
                if (s.Expression() == null) { if (expected != "void") { Error("return value required"); } }
                else { string actual = Expression(s.Expression()); if (expected == "void") { Error("void method cannot return a value"); } else { Require(actual, expected, "return type mismatch"); } } return;
            }
            if (k == IrStatement.KindExpressionStatement() || k == IrStatement.KindThrowStatement()) { Expression(s.Expression()); return; }
            if (k == IrStatement.KindIfStatement()) { string condition = Expression(s.Condition()); Require(condition, "bool", "condition must be bool"); Scoped(s.ThenStatement()); Scoped(s.ElseStatement()); return; }
            if (k == IrStatement.KindWhileStatement()) { string condition = Expression(s.Condition()); Require(condition, "bool", "condition must be bool"); loops = loops + 1; Scoped(s.Body()); loops = loops - 1; return; }
            if (k == IrStatement.KindBreakStatement() || k == IrStatement.KindContinueStatement()) { if (loops == 0) { Error("break or continue outside loop"); } return; }
            if (k == IrStatement.KindTryStatement()) {
                Scoped(s.Body()); int saved = count; int savedScope = scope; scope = count;
                DeclareType(s.CatchType(), false); Add(s.CatchName(), s.CatchType().DisplayName()); Statement(s.CatchBlock()); count = saved; scope = savedScope;
            }
        }
        private bool Returns(IrStatement s) {
            if (s == null) { return false; }
            if (s.Kind() == IrStatement.KindReturnStatement() || s.Kind() == IrStatement.KindThrowStatement()) { return true; }
            if (s.Kind() == IrStatement.KindBlock()) { int i = 0; while (i < s.Statements().Length) { if (Returns(s.Statements()[i])) { return true; } i = i + 1; } }
            if (s.Kind() == IrStatement.KindIfStatement()) { return Returns(s.ThenStatement()) && Returns(s.ElseStatement()); }
            if (s.Kind() == IrStatement.KindTryStatement()) { return Returns(s.Body()) && Returns(s.CatchBlock()); }
            return false;
        }
        private IrField Field(string type, string name) {
            IrClass cl = module.FindClass(type); if (cl == null) { return null; }
            int i = 0; while (i < cl.Fields().Length) { if (cl.Fields()[i].Name() == name) { return cl.Fields()[i]; } i = i + 1; } return null;
        }
        private IrMethod Method(string type, string name) {
            IrClass cl = module.FindClass(type); if (cl == null) { return null; }
            int i = 0; while (i < cl.Methods().Length) { if (cl.Methods()[i].Name() == name) { return cl.Methods()[i]; } i = i + 1; } return null;
        }
        private string Qualified(IrExpression e) {
            if (e == null) { return ""; }
            if (e.Kind() == IrExpression.KindName()) { return e.Name(); }
            if (e.Kind() == IrExpression.KindMemberAccess()) { string left = Qualified(e.Receiver()); if (left != "") { return left + "." + e.MemberName(); } }
            return "";
        }
        private string RootName(string name) { string result = ""; int i = 0; while (i < name.Length) { if (name[i] == ".") { return result; } result = result + name[i]; i = i + 1; } return result; }
        private bool TypeReceiver(IrExpression e) {
            string name = Qualified(e); if (name == "") { return false; }
            if (Local(RootName(name)) >= 0 || Field(owner, RootName(name)) != null || RootName(name) == "this") { return false; }
            return module.HasType(module.ResolveType(name, owner));
        }
        private string Expression(IrExpression e) {
            if (e == null) { return "void"; }
            string result = ExpressionType(e); e.SetResultType(result); return result;
        }
        private string ExpressionType(IrExpression e) {
            int k = e.Kind();
            if (k == IrExpression.KindLiteral()) { if (e.LiteralKind() == "number") { return "int"; } return e.LiteralKind(); }
            if (k == IrExpression.KindName()) {
                if (e.Name() == "this") { if (method.IsStatic()) { Error("this is unavailable in a static method"); return "<error>"; } return owner; }
                int i = Local(e.Name()); if (i >= 0) { return types[i]; }
                IrField field = Field(owner, e.Name());
                if (field != null) { if (!field.IsStatic() && method.IsStatic()) { Error("instance field requires an object receiver"); } e.SetResolvedOwner(owner); return field.Type().DisplayName(); }
                Error("undefined name '" + e.Name() + "' in " + owner + "." + method.Name()); return "<error>";
            }
            if (k == IrExpression.KindMemberAccess()) {
                bool typeReceiver = TypeReceiver(e.Receiver()); string receiver = "";
                if (typeReceiver) { receiver = module.ResolveType(Qualified(e.Receiver()), owner); e.Receiver().SetResultType(receiver); }
                else { receiver = Expression(e.Receiver()); }
                e.SetResolvedOwner(receiver);
                IrEnum en = module.FindEnum(receiver);
                if (en != null && typeReceiver) { int i = 0; while (i < en.Members().Length) { if (en.Members()[i].Name() == e.MemberName()) { return receiver; } i = i + 1; } }
                if ((receiver == "string" || module.IsArray(receiver)) && e.MemberName() == "Length") { return "int"; }
                IrField field = Field(receiver, e.MemberName());
                if (field != null) {
                    if (field.IsPrivate() && receiver != owner) { Error("private field is inaccessible: " + receiver + "." + field.Name()); }
                    if (field.IsStatic() != typeReceiver) { Error("field receiver does not match static or instance declaration"); }
                    return field.Type().DisplayName();
                }
                if (receiver != "<error>") { Error("undefined member '" + e.MemberName() + "' on " + receiver); } return "<error>";
            }
            if (k == IrExpression.KindInvocation()) { return Call(e); }
            if (k == IrExpression.KindObjectCreation()) {
                DeclareType(e.Type(), false); string type = e.Type().DisplayName(); e.SetResolvedOwner(type);
                IrClass cl = module.FindClass(type); if (cl == null) { Error("object creation requires a class type"); return "<error>"; }
                if (cl.IsInterface()) { Error("cannot instantiate an interface: " + type); return "<error>"; }
                IrMethod constructor = Method(type, module.SimpleName(type));
                if (constructor == null) { if (e.Arguments().Length != 0) { Error("default constructor takes no arguments"); } Arguments(e.Arguments()); }
                else { if (constructor.IsPrivate() && type != owner) { Error("private constructor is inaccessible: " + type); } CheckArguments(e.Arguments(), constructor.Parameters(), constructor.Name()); }
                return type;
            }
            if (k == IrExpression.KindArrayCreation()) { DeclareType(e.Type(), false); string size = Expression(e.Size()); Require(size, "int", "array size must be int"); return e.Type().DisplayName() + "[]"; }
            if (k == IrExpression.KindIndex()) {
                string type = Expression(e.Receiver()); string index = Expression(e.Index()); Require(index, "int", "index must be int");
                if (type == "string") { return "string"; } if (module.IsArray(type)) { return module.Element(type); }
                if (type != "<error>") { Error("indexing requires an array or string"); } return "<error>";
            }
            if (k == IrExpression.KindAssignment()) {
                string target = Expression(e.Target()); string value = Expression(e.Value());
                if (!Writable(e.Target())) { Error("assignment target is not writable"); }
                Require(value, target, "assignment type mismatch"); return target;
            }
            if (k == IrExpression.KindCast()) {
                DeclareType(e.CastType(), false); string actual = Expression(e.CastExpression()); string expected = e.CastType().DisplayName();
                if (!(Numeric(actual) && Numeric(expected)) && actual != expected && actual != "<error>") { Error("invalid cast"); } return expected;
            }
            if (k == IrExpression.KindSizeOf()) { DeclareType(e.SizeOfType(), false); return "int"; }
            if (k == IrExpression.KindUnary()) {
                string actual = Expression(e.UnaryOperand());
                if (e.UnaryOperatorKind() == IrOperator.BangToken()) { Require(actual, "bool", "logical operand must be bool"); return "bool"; }
                if (!Numeric(actual) && actual != "<error>") { Error("unary arithmetic requires numeric operand"); } return actual;
            }
            string left = Expression(e.Left()); string right = Expression(e.Right()); int op = e.OperatorKind();
            if (op == IrOperator.AmpersandAmpersandToken() || op == IrOperator.PipePipeToken()) { Require(left, "bool", "logical operand must be bool"); Require(right, "bool", "logical operand must be bool"); return "bool"; }
            if (op == IrOperator.PlusToken() && (left == "string" || right == "string")) {
                if (!Printable(left) || !Printable(right)) { Error("string concatenation requires printable values"); } return "string";
            }
            if (op == IrOperator.EqualsEqualsToken() || op == IrOperator.BangEqualsToken()) {
                if (!Assignable(left, right) && !Assignable(right, left)) { Error("equality operands have incompatible types"); } return "bool";
            }
            if ((!Numeric(left) || !Numeric(right)) && left != "<error>" && right != "<error>") { Error("arithmetic or comparison operands must be numeric"); }
            if (op == IrOperator.LessToken() || op == IrOperator.LessEqualsToken() || op == IrOperator.GreaterToken() || op == IrOperator.GreaterEqualsToken()) { return "bool"; }
            return "int";
        }
        private bool Numeric(string type) { return module.Numeric(type) || module.FindEnum(type) != null; }
        private bool Printable(string type) { return type == "string" || type == "bool" || Numeric(type) || type == "<error>"; }
        private bool Writable(IrExpression e) {
            if (e.Kind() == IrExpression.KindName()) { return e.Name() != "this"; }
            if (e.Kind() == IrExpression.KindIndex()) { return module.IsArray(e.Receiver().ResultType()); }
            if (e.Kind() == IrExpression.KindMemberAccess()) { return Field(e.ResolvedOwner(), e.MemberName()) != null; }
            return false;
        }
        private void Arguments(IrExpression[] args) { int i = 0; while (i < args.Length) { Expression(args[i]); i = i + 1; } }
        private void CheckArguments(IrExpression[] args, IrParameter[] parameters, string name) {
            if (args.Length != parameters.Length) { Error("wrong argument count calling '" + name + "'"); }
            int i = 0; while (i < args.Length) { string type = Expression(args[i]); if (i < parameters.Length) { Require(type, parameters[i].Type().DisplayName(), "argument type mismatch calling '" + name + "'"); } i = i + 1; }
        }
        private string Intrinsic(IrExpression e, string name, string first, string second, string result) {
            int expected = 0; if (first != "") { expected = 1; } if (second != "") { expected = 2; }
            if (e.Arguments().Length != expected) { Error("wrong argument count calling '" + name + "'"); }
            int i = 0; while (i < e.Arguments().Length) { string type = Expression(e.Arguments()[i]); string required = first; if (i == 1) { required = second; } if (i < expected) { Require(type, required, "argument type mismatch calling '" + name + "'"); } i = i + 1; }
            e.SetResolvedOwner(module.NamespaceOf(name)); return result;
        }
        private string Call(IrExpression e) {
            string qualified = Qualified(e.Target());
            if (qualified == "System.Console.WriteLine" || qualified == "System.Console.Write") {
                int n = e.Arguments().Length;
                if (n > 1 || (n == 0 && qualified == "System.Console.Write")) { Error("console output requires one value"); }
                int i = 0; while (i < n) { if (!Printable(Expression(e.Arguments()[i]))) { Error("console output requires a printable value"); } i = i + 1; }
                e.SetResolvedOwner("System.Console"); return "void";
            }
            if (qualified == "System.Console.ReadLine") { return Intrinsic(e, qualified, "", "", "string"); }
            if (qualified == "System.IO.File.Exists") { return Intrinsic(e, qualified, "string", "", "bool"); }
            if (qualified == "System.IO.File.ReadAllText") { return Intrinsic(e, qualified, "string", "", "string"); }
            if (qualified == "System.IO.File.ReadAllBytes") { return Intrinsic(e, qualified, "string", "", "byte[]"); }
            if (qualified == "System.IO.File.WriteAllText") { return Intrinsic(e, qualified, "string", "string", "void"); }
            if (qualified == "System.IO.File.WriteAllBytes") { return Intrinsic(e, qualified, "string", "byte[]", "void"); }
            if (qualified == "System.Convert.ToInt32") { return Intrinsic(e, qualified, "string", "", "int"); }
            if (qualified == "System.Runtime.GC.Collect") { return Intrinsic(e, qualified, "", "", "void"); }
            if (qualified == "System.Runtime.GC.GetAllocatedBytes") { return Intrinsic(e, qualified, "", "", "int"); }
            string type = owner; string name = ""; bool typeReceiver = false; bool explicitReceiver = false;
            IrExpression target = e.Target();
            if (target.Kind() == IrExpression.KindName()) { name = target.Name(); }
            else if (target.Kind() == IrExpression.KindMemberAccess()) {
                explicitReceiver = true; typeReceiver = TypeReceiver(target.Receiver()); name = target.MemberName();
                if (typeReceiver) { type = module.ResolveType(Qualified(target.Receiver()), owner); target.Receiver().SetResultType(type); }
                else { type = Expression(target.Receiver()); }
            } else { Error("invalid call target"); Arguments(e.Arguments()); return "<error>"; }
            IrMethod callee = Method(type, name);
            if (callee == null) { if (type != "<error>") { Error("undefined method: " + type + "." + name); } Arguments(e.Arguments()); return "<error>"; }
            if (callee.IsPrivate() && type != owner) { Error("private method is inaccessible: " + type + "." + name); }
            if (explicitReceiver) { if (callee.IsStatic() != typeReceiver) { Error("method receiver does not match static or instance declaration"); } }
            else if (!callee.IsStatic() && method.IsStatic()) { Error("instance method requires an object receiver"); }
            e.SetResolvedOwner(type); target.SetResolvedOwner(type); target.SetResultType(callee.ReturnType().DisplayName());
            CheckArguments(e.Arguments(), callee.Parameters(), name); return callee.ReturnType().DisplayName();
        }
    }
}
