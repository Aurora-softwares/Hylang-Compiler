using Hydrogen.Compiler.Text;

namespace Hydrogen.Compiler.IR {
	public class IrUnit {
		private IrImport[] usings;
		private IrNamespace[] namespaces;
		private IrClass[] classes;
		private IrEnum[] enums;
		private IrInterface[] interfaces;

		public IrUnit(
			IrImport[] inputUsings,
			IrNamespace[] inputNamespaces,
			IrClass[] inputClasses,
			IrEnum[] inputEnums,
			IrInterface[] inputInterfaces
		) {
			usings = inputUsings;
			namespaces = inputNamespaces;
			classes = inputClasses;
			enums = inputEnums;
			interfaces = inputInterfaces;
		}

		public IrImport[] Usings() {
			return usings;
		}

		public IrNamespace[] Namespaces() {
			return namespaces;
		}

		public IrClass[] Classes() {
			return classes;
		}

		public IrEnum[] Enums() {
			return enums;
		}

		public IrInterface[] Interfaces() {
			return interfaces;
		}
	}

	public class IrImport {
		private string name;

		public IrImport(string inputName) {
			name = inputName;
		}

		public string Name() {
			return name;
		}
	}

	public class IrNamespace {
		private string name;
		private IrClass[] classes;
		private IrEnum[] enums;
		private IrInterface[] interfaces;

		public IrNamespace( string inputName, IrClass[] inputClasses, IrEnum[] inputEnums, IrInterface[] inputInterfaces ) {
			name = inputName;
			classes = inputClasses;
			enums = inputEnums;
			interfaces = inputInterfaces;
		}

		public string Name() { return name; }

		public IrClass[] Classes() { return classes; }

		public IrEnum[] Enums() { return enums; }

		public IrInterface[] Interfaces() { return interfaces; }
	}

	public class IrClass {
        private bool isInterface;
        public bool IsInterface() { return isInterface; }
        public void SetInterface(bool value) { isInterface = value; }
        private bool isStruct;
        public bool IsStruct() { return isStruct; }
        public void SetStruct(bool value) { isStruct = value; }
        private string baseType;
        public string BaseType() { return baseType; }
        public void SetBaseType(string value) { baseType = value; }
        private string[] interfaceTypes;
        public string[] InterfaceTypes() { return interfaceTypes; }
        public void SetInterfaceTypes(string[] value) { interfaceTypes = value; }
        private IrImport[] imports;
        public void SetImports(IrImport[] value) { imports = value; }
        public IrImport[] Imports() { return imports; }
		private string name;
		private IrField[] fields;
		private IrMethod[] methods;

		public IrClass(string inputName, IrField[] inputFields, IrMethod[] inputMethods) {
			name = inputName;
			baseType = "";
			interfaceTypes = new string[0];
			fields = inputFields;
			methods = inputMethods;
		}

		public string Name() { return name; }

		public IrField[] Fields() { return fields; }

		public IrMethod[] Methods() { return methods; }
	}

	// Keep fields in the self-hosted syntax tree even before the native backend
	// materialises an object layout.  Dropping them made it impossible for later
	// phases to compile the compiler's own stateful classes faithfully.
	public class IrField {
		private IrType type;
		private string name;
		private bool isStatic;
        private bool isPrivate;
		private IrExpression initializer;

		public IrField(IrType inputType, string inputName, bool inputIsStatic, IrExpression inputInitializer) {
			type = inputType;
			name = inputName;
			isStatic = inputIsStatic;
			initializer = inputInitializer;
		}

		public IrType Type() { return type; }
		public string Name() { return name; }
		public bool IsStatic() { return isStatic; }
        public bool IsPrivate() { return isPrivate; }
        public void SetPrivate(bool value) { isPrivate = value; }
		public IrExpression Initializer() { return initializer; }
	}

	public class IrMembers {
		private IrField[] fields;
		private IrMethod[] methods;

		public IrMembers(IrField[] inputFields, IrMethod[] inputMethods) {
			fields = inputFields;
			methods = inputMethods;
		}

		public IrField[] Fields() { return fields; }
		public IrMethod[] Methods() { return methods; }
	}

	public class IrMethod {
		private string name;
		private bool isStatic;
        private bool isPrivate;
		private bool isVirtual;
		private bool isOverride;
		private IrType returnType;

		private IrParameter[] parameters;
		private IrStatement body;
		private string constructorInitializerKind;
		private IrExpression[] constructorInitializerArguments;
		private string constructorInitializerSignature;

		public IrMethod(string inputName, bool inputIsStatic, bool inputIsVirtual, bool inputIsOverride, IrType inputReturnType, IrParameter[] inputParameters, IrStatement inputBody) {
			name = inputName;
			isStatic = inputIsStatic;
			isVirtual = inputIsVirtual;
			isOverride = inputIsOverride;
			returnType = inputReturnType;
			parameters = inputParameters;
			body = inputBody;
			constructorInitializerKind = "";
			constructorInitializerArguments = new IrExpression[0];
			constructorInitializerSignature = "";
		}

		public string Name() { return name; }

		public bool IsStatic() { return isStatic; }
        public bool IsPrivate() { return isPrivate; }
        public void SetPrivate(bool value) { isPrivate = value; }

		public bool IsVirtual() { return isVirtual; }

		public bool IsOverride() { return isOverride; }

		public IrType ReturnType() { return returnType; }

		public IrParameter[] Parameters() { return parameters; }

		public IrStatement Body() { return body; }
        public void SetBody(IrStatement value) { body = value; }
		public string ConstructorInitializerKind() { return constructorInitializerKind; }
		public IrExpression[] ConstructorInitializerArguments() { return constructorInitializerArguments; }
		public string ConstructorInitializerSignature() { return constructorInitializerSignature; }
		public void SetConstructorInitializer(string kind, IrExpression[] arguments) {
			constructorInitializerKind = kind; constructorInitializerArguments = arguments;
		}
		public void SetConstructorInitializerSignature(string value) { constructorInitializerSignature = value; }
	}

	public class IrInterface {
		private string name;
		private IrMethod[] methods;

		public IrInterface(string inputName, IrMethod[] inputMethods) {
			name = inputName;
			methods = inputMethods;
		}

		public string Name() {
			return name;
		}

		public IrMethod[] Methods() {
			return methods;
		}
	}

	public class IrParameter {
		private IrType type;
		private string name;

		public IrParameter(IrType inputType, string inputName) {
			type = inputType;
			name = inputName;
		}

		public IrType Type() { return type; }

		public string Name() { return name; }
	}

	public class IrType {
		private string displayName;
		private int line;
		private int column;
		private TextSpan span;

		public IrType(string inputDisplayName) {
			displayName = inputDisplayName;
		}

		public string DisplayName() { return displayName; }
        public void SetName(string value) { displayName = value; }
		public int Line() { return line; }
		public int Column() { return column; }
		public TextSpan Span() { return span; }
		public void SetLocation(int inputLine, int inputColumn, int start, int length) {
			line = inputLine; column = inputColumn; span = new TextSpan(start, length);
		}
	}

	public class IrStatement {
		public static int KindBlock() { return 1; }
		public static int KindIfStatement() { return 2; }
		public static int KindReturnStatement() { return 3; }
		public static int KindExpressionStatement() { return 4; }
		public static int KindVariableDeclaration() { return 5; }
		public static int KindWhileStatement() { return 6; }
		public static int KindBreakStatement() { return 7; }
		public static int KindContinueStatement() { return 8; }
		public static int KindTryStatement() { return 9; }
		public static int KindThrowStatement() { return 10; }
		public static int KindForStatement() { return 11; }

		private int kind;
		private IrStatement[] statements;
		private IrExpression condition;
		private IrStatement thenStatement;
		private IrStatement elseStatement;
		private IrStatement body;
		private IrExpression expression;
		private IrType type;
		private string name;
		private IrExpression initializer;
		private IrStatement catchBlock;
		private IrType catchType;
		private string catchName;
		private IrStatement forInitializer;
		private IrExpression forIncrement;
		private int line;
		private int column;
		private TextSpan span;

		public IrStatement(int inputKind) {
			kind = inputKind;
		}

		public int Kind() { return kind; }
		public IrStatement[] Statements() { return statements; }
		public IrExpression Condition() { return condition; }
		public IrStatement ThenStatement() { return thenStatement; }
		public IrStatement ElseStatement() { return elseStatement; }
		public IrStatement Body() { return body; }
        public void SetBody(IrStatement value) { body = value; }
		public IrExpression Expression() { return expression; }
		public IrType Type() { return type; }
		public string Name() { return name; }
		public IrExpression Initializer() { return initializer; }
		public IrStatement CatchBlock() { return catchBlock; }
		public IrType CatchType() { return catchType; }
		public string CatchName() { return catchName; }
		public IrStatement ForInitializer() { return forInitializer; }
		public IrExpression ForIncrement() { return forIncrement; }
		public int Line() { return line; }
		public int Column() { return column; }
		public TextSpan Span() { return span; }
		public void SetLocation(int inputLine, int inputColumn, int start, int length) {
			line = inputLine; column = inputColumn; span = new TextSpan(start, length);
		}

		public static IrStatement Block(IrStatement[] items) {
			IrStatement node = new IrStatement(KindBlock());
			node.statements = items;
			return node;
		}

		public static IrStatement If(IrExpression inputCondition, IrStatement inputThen, IrStatement inputElse) {
			IrStatement node = new IrStatement(KindIfStatement());
			node.condition = inputCondition;
			node.thenStatement = inputThen;
			node.elseStatement = inputElse;
			return node;
		}

		public static IrStatement Return(IrExpression inputExpression) {
			IrStatement node = new IrStatement(KindReturnStatement());
			node.expression = inputExpression;
			return node;
		}

		public static IrStatement ExpressionStatement(IrExpression inputExpression) {
			IrStatement node = new IrStatement(KindExpressionStatement());
			node.expression = inputExpression;
			return node;
		}

		public static IrStatement VariableDeclaration(IrType inputType, string inputName, IrExpression inputInitializer) {
			IrStatement node = new IrStatement(KindVariableDeclaration());
			node.type = inputType;
			node.name = inputName;
			node.initializer = inputInitializer;
			return node;
		}

		public static IrStatement While(IrExpression inputCondition, IrStatement inputBody) {
			IrStatement node = new IrStatement(KindWhileStatement());
			node.condition = inputCondition;
			node.body = inputBody;
			return node;
		}

		public static IrStatement For(IrStatement inputInitializer, IrExpression inputCondition, IrExpression inputIncrement, IrStatement inputBody) {
			IrStatement node = new IrStatement(KindForStatement());
			node.forInitializer = inputInitializer;
			node.condition = inputCondition;
			node.forIncrement = inputIncrement;
			node.body = inputBody;
			return node;
		}

		public static IrStatement Break() {
			return new IrStatement(KindBreakStatement());
		}

		public static IrStatement Continue() {
			return new IrStatement(KindContinueStatement());
		}

		public static IrStatement Try(IrStatement inputBody, IrType inputCatchType, string inputCatchName, IrStatement inputCatchBlock) {
			IrStatement node = new IrStatement(KindTryStatement());
			node.body = inputBody;
			node.catchType = inputCatchType;
			node.catchName = inputCatchName;
			node.catchBlock = inputCatchBlock;
			return node;
		}

		public static IrStatement Throw(IrExpression inputExpression) {
			IrStatement node = new IrStatement(KindThrowStatement());
			node.expression = inputExpression;
			return node;
		}
	}

	public class IrExpression {
        private string resultType;
        private string resolvedOwner;
        private string resolvedSignature;
        public string ResultType() { return resultType; }
        public void SetResultType(string value) { resultType = value; }
        public string ResolvedOwner() { return resolvedOwner; }
        public void SetResolvedOwner(string value) { resolvedOwner = value; }
        public string ResolvedSignature() { return resolvedSignature; }
        public void SetResolvedSignature(string value) { resolvedSignature = value; }
		public static int KindName() { return 1; }
		public static int KindLiteral() { return 2; }
		public static int KindMemberAccess() { return 3; }
		public static int KindInvocation() { return 4; }
		public static int KindAssignment() { return 5; }
		public static int KindBinary() { return 6; }
		public static int KindIndex() { return 7; }
		public static int KindObjectCreation() { return 8; }
		public static int KindArrayCreation() { return 9; }
		public static int KindCast() { return 10; }
		public static int KindUnary() { return 11; }
		public static int KindSizeOf() { return 12; }

		private int kind;
		private string name;
		private string literalKind;
		private string literalText;
		private IrExpression receiver;
		private string memberName;
		private IrExpression target;
		private IrExpression[] arguments;
		private IrExpression value;
		private IrExpression left;
		private int op;
		private IrExpression right;
		private IrExpression index;
		private IrType type;
		private IrExpression size;
		private IrType castType;
		private IrExpression castExpression;
		private int unaryOp;
		private IrExpression unaryOperand;
		private IrType sizeOfType;
		private int line;
		private int column;
		private TextSpan span;

		public IrExpression(int inputKind) {
			kind = inputKind;
		}

		public int Kind() { return kind; }
		public string Name() { return name; }
		public string LiteralKind() { return literalKind; }
		public string LiteralText() { return literalText; }
		public IrExpression Receiver() { return receiver; }
		public string MemberName() { return memberName; }
		public IrExpression Target() { return target; }
		public IrExpression[] Arguments() { return arguments; }
		public IrExpression Value() { return value; }
		public IrExpression Left() { return left; }
		public int OperatorKind() { return op; }
		public IrExpression Right() { return right; }
		public IrExpression Index() { return index; }
		public IrType Type() { return type; }
		public IrExpression Size() { return size; }
		public IrType CastType() { return castType; }
		public IrExpression CastExpression() { return castExpression; }
		public int UnaryOperatorKind() { return unaryOp; }
		public IrExpression UnaryOperand() { return unaryOperand; }
		public IrType SizeOfType() { return sizeOfType; }
		public int Line() { return line; }
		public int Column() { return column; }
		public TextSpan Span() { return span; }
		public void SetLocation(int inputLine, int inputColumn, int start, int length) {
			line = inputLine; column = inputColumn; span = new TextSpan(start, length);
		}

		public static IrExpression NameExpr(string inputName) {
			IrExpression node = new IrExpression(KindName());
			node.name = inputName;
			return node;
		}

		public static IrExpression Literal(string inputKind, string inputText) {
			IrExpression node = new IrExpression(KindLiteral());
			node.literalKind = inputKind;
			node.literalText = inputText;
			return node;
		}

		public static IrExpression MemberAccess(IrExpression inputReceiver, string inputMemberName) {
			IrExpression node = new IrExpression(KindMemberAccess());
			node.receiver = inputReceiver;
			node.memberName = inputMemberName;
			return node;
		}

		public static IrExpression Invocation(IrExpression inputTarget, IrExpression[] inputArguments) {
			IrExpression node = new IrExpression(KindInvocation());
			node.target = inputTarget;
			node.arguments = inputArguments;
			return node;
		}

		public static IrExpression Assignment(IrExpression inputTarget, IrExpression inputValue) {
			IrExpression node = new IrExpression(KindAssignment());
			node.target = inputTarget;
			node.value = inputValue;
			return node;
		}

		public static IrExpression Binary(IrExpression inputLeft, int inputOp, IrExpression inputRight) {
			IrExpression node = new IrExpression(KindBinary());
			node.left = inputLeft;
			node.op = inputOp;
			node.right = inputRight;
			return node;
		}

		public static IrExpression IndexExpr(IrExpression inputReceiver, IrExpression inputIndex) {
			IrExpression node = new IrExpression(KindIndex());
			node.receiver = inputReceiver;
			node.index = inputIndex;
			return node;
		}

		public static IrExpression ObjectCreation(IrType inputType, IrExpression[] inputArguments) {
			IrExpression node = new IrExpression(KindObjectCreation());
			node.type = inputType;
			node.arguments = inputArguments;
			return node;
		}

		public static IrExpression ArrayCreation(IrType inputElementType, IrExpression inputSize) {
			IrExpression node = new IrExpression(KindArrayCreation());
			node.type = inputElementType;
			node.size = inputSize;
			return node;
		}

		public static IrExpression Cast(IrType inputType, IrExpression inputExpression) {
			IrExpression node = new IrExpression(KindCast());
			node.castType = inputType;
			node.castExpression = inputExpression;
			return node;
		}

		public static IrExpression Unary(int inputOp, IrExpression inputOperand) {
			IrExpression node = new IrExpression(KindUnary());
			node.unaryOp = inputOp;
			node.unaryOperand = inputOperand;
			return node;
		}

		public static IrExpression SizeOf(IrType inputType) {
			IrExpression node = new IrExpression(KindSizeOf());
			node.sizeOfType = inputType;
			return node;
		}
	}

	public class IrEnum {
		private string name;
		private IrEnumMember[] members;

		public IrEnum(string inputName, IrEnumMember[] inputMembers) {
			name = inputName;
			members = inputMembers;
		}

		public string Name() {
			return name;
		}

		public IrEnumMember[] Members() {
			return members;
		}
	}

	public class IrEnumMember {
		private string name;
		private int value;
		private bool hasExplicitValue;

		public IrEnumMember(string inputName, int inputValue, bool inputHasExplicitValue) {
			name = inputName;
			value = inputValue;
			hasExplicitValue = inputHasExplicitValue;
		}

		public string Name() {
			return name;
		}

		public int Value() {
			return value;
		}

		public bool HasExplicitValue() {
			return hasExplicitValue;
		}
	}
}
