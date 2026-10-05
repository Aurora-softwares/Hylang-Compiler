namespace Hydrogen.Compiler.IR {
    // Structured executable IR. Imports belong to the declaring source file.
    public class IrModule {
        private IrFunction[] functions;
        private IrUnit root;
        private string namespaceName;
        private string namespaceValue;
        public IrModule(IrFunction[] inputFunctions) { functions = inputFunctions; }
        public IrFunction[] Functions() { return functions; }
        public IrUnit Root() { return root; }
        public void SetRoot(IrUnit value) { root = value; }
        public void SetFunctions(IrFunction[] value) { functions = value; }
        public IrClass FindClass(string name) {
            int i = 0;
            while (i < root.Classes().Length) { if (root.Classes()[i].Name() == name) { return root.Classes()[i]; } i = i + 1; }
            return null;
        }
        public IrEnum FindEnum(string name) {
            int i = 0;
            while (i < root.Enums().Length) { if (root.Enums()[i].Name() == name) { return root.Enums()[i]; } i = i + 1; }
            return null;
        }
        public bool HasType(string name) { return FindClass(name) != null || FindEnum(name) != null; }
        public string NamespaceOf(string name) {
            // Body checking repeatedly resolves names in the same owner. Reuse
            // its immutable namespace rather than allocating every prefix again.
            if (name == namespaceName) { return namespaceValue; }
            int last = -1; int i = 0;
            while (i < name.Length) { if (name[i] == ".") { last = i; } i = i + 1; }
            namespaceName = name;
            namespaceValue = Slice(name, last);
            return namespaceValue;
        }
        public string SimpleName(string name) {
            string result = ""; int i = 0;
            while (i < name.Length) { if (name[i] == ".") { result = ""; } else { result = result + name[i]; } i = i + 1; } return result;
        }
        public bool IsArray(string name) {
            if (name.Length < 2) { return false; }
            return name[name.Length - 2] == "[" && name[name.Length - 1] == "]";
        }
        public string Element(string name) { return Slice(name, name.Length - 2); }
        private string Slice(string name, int length) {
            string result = ""; int i = 0;
            while (i < length) { result = result + name[i]; i = i + 1; } return result;
        }
        public bool Numeric(string name) {
            return name == "byte" || name == "sbyte" || name == "short" || name == "ushort" || name == "int" || name == "uint" || name == "long" || name == "ulong" || name == "nint" || name == "nuint";
        }
        public bool Reference(string name) { return name == "string" || IsArray(name) || FindClass(name) != null; }
        public string ResolveType(string name, string owner) {
            if (IsArray(name)) {
                string element = ResolveType(Element(name), owner);
                if (element == "<unknown>" || element == "<ambiguous>") { return element; }
                return element + "[]";
            }
            if (Numeric(name) || name == "bool" || name == "string" || name == "void" || name == "var" || name == "null") { return name; }
            string ns = NamespaceOf(owner);
            if (ns != "") { if (HasType(ns + "." + name)) { return ns + "." + name; } }
            if (HasType(name)) { return name; }
            IrClass declaring = FindClass(owner);
            string found = "";
            if (declaring != null) {
                IrImport[] imports = declaring.Imports(); int i = 0;
                while (i < imports.Length) {
                    string candidate = imports[i].Name() + "." + name;
                    if (HasType(candidate)) {
                        if (found != "" && found != candidate) { return "<ambiguous>"; }
                        found = candidate;
                    }
                    i = i + 1;
                }
            }
            if (found != "") { return found; }
            return "<unknown>";
        }
        public string ToDebugText() {
            string text = "IrModule\n"; int i = 0;
            while (i < functions.Length) { text = text + functions[i].ToDebugText(); i = i + 1; }
            return text;
        }
    }
    public class IrBodyPrinter {
        public string Statement(IrStatement s, string indent) {
            if (s == null) { return ""; }
            int k = s.Kind(); string text = "";
            if (k == IrStatement.KindBlock()) {
                int i = 0; while (i < s.Statements().Length) { text = text + Statement(s.Statements()[i], indent); i = i + 1; } return text;
            }
            if (k == IrStatement.KindVariableDeclaration()) { string valueText = Expression(s.Initializer()); return indent + "local " + s.Name() + " : " + s.Type().DisplayName() + " = " + valueText + "\n"; }
            if (k == IrStatement.KindReturnStatement()) { string valueText = Expression(s.Expression()); return indent + "return " + valueText + "\n"; }
            if (k == IrStatement.KindExpressionStatement()) { string valueText = Expression(s.Expression()); return indent + valueText + "\n"; }
            if (k == IrStatement.KindIfStatement()) { string condition = Expression(s.Condition());
                string thenText = Statement(s.ThenStatement(), indent + "  ");
                string elseText = Statement(s.ElseStatement(), indent + "  ");
                return indent + "if " + condition + "\n" + thenText + indent + "else\n" + elseText; }
            if (k == IrStatement.KindWhileStatement()) { string condition = Expression(s.Condition());
                string bodyText = Statement(s.Body(), indent + "  ");
                return indent + "while " + condition + "\n" + bodyText; }
            if (k == IrStatement.KindBreakStatement()) { return indent + "break\n"; }
            if (k == IrStatement.KindContinueStatement()) { return indent + "continue\n"; }
            if (k == IrStatement.KindTryStatement()) { string bodyText = Statement(s.Body(), indent + "  ");
                string catchText = Statement(s.CatchBlock(), indent + "  ");
                return indent + "try\n" + bodyText + indent + "catch\n" + catchText; }
            string valueText = Expression(s.Expression()); return indent + "throw " + valueText + "\n";
        }
        public string Expression(IrExpression e) {
            if (e == null) { return "void"; }
            int k = e.Kind(); string text = "";
            if (k == IrExpression.KindLiteral()) { text = "literal(" + e.LiteralText() + ")"; }
            else if (k == IrExpression.KindName()) { text = "load(" + e.Name() + ")"; }
            else if (k == IrExpression.KindMemberAccess()) { string receiverText = Expression(e.Receiver()); text = "field(" + receiverText + ", " + e.MemberName() + ")"; }
            else if (k == IrExpression.KindIndex()) { string leftText = Expression(e.Receiver());
                string rightText = Expression(e.Index());
                text = "index(" + leftText + ", " + rightText + ")"; }
            else if (k == IrExpression.KindAssignment()) { string leftText = Expression(e.Target());
                string rightText = Expression(e.Value());
                text = "store(" + leftText + ", " + rightText + ")"; }
            else if (k == IrExpression.KindBinary()) { string leftText = Expression(e.Left());
                string rightText = Expression(e.Right());
                text = "binary(" + (int)e.OperatorKind() + ", " + leftText + ", " + rightText + ")"; }
            else if (k == IrExpression.KindUnary()) { string operandText = Expression(e.UnaryOperand()); text = "unary(" + (int)e.UnaryOperatorKind() + ", " + operandText + ")"; }
            else if (k == IrExpression.KindArrayCreation()) { string sizeText = Expression(e.Size()); text = "newarray(" + e.Type().DisplayName() + ", " + sizeText + ")"; }
            else if (k == IrExpression.KindCast()) { string valueText = Expression(e.CastExpression()); text = "cast(" + e.CastType().DisplayName() + ", " + valueText + ")"; }
            else if (k == IrExpression.KindSizeOf()) { text = "sizeof(" + e.SizeOfType().DisplayName() + ")"; }
            else {
                if (k == IrExpression.KindObjectCreation()) { text = "newobject(" + e.Type().DisplayName(); }
                else { text = "call(" + e.ResolvedOwner() + "." + CallName(e.Target()); }
                int i = 0; while (i < e.Arguments().Length) { string argumentText = Expression(e.Arguments()[i]); text = text + ", " + argumentText; i = i + 1; } text = text + ")";
            }
            return text + " : " + e.ResultType();
        }
        private string CallName(IrExpression e) { if (e.Kind() == IrExpression.KindName()) { return e.Name(); } return e.MemberName(); }
    }
}
