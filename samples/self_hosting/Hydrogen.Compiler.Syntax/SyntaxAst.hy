namespace Hydrogen.Compiler.Syntax {
	public class CompilationUnitSyntax {
		private UsingDirectiveSyntax[] usings;
		private NamespaceDeclarationSyntax[] namespaces;
		private ClassDeclarationSyntax[] classes;
		private EnumDeclarationSyntax[] enums;
		private InterfaceDeclarationSyntax[] interfaces;

		public CompilationUnitSyntax(
			UsingDirectiveSyntax[] inputUsings,
			NamespaceDeclarationSyntax[] inputNamespaces,
			ClassDeclarationSyntax[] inputClasses,
			EnumDeclarationSyntax[] inputEnums,
			InterfaceDeclarationSyntax[] inputInterfaces
		) {
			usings = inputUsings;
			namespaces = inputNamespaces;
			classes = inputClasses;
			enums = inputEnums;
			interfaces = inputInterfaces;
		}

		public UsingDirectiveSyntax[] Usings() {
			return usings;
		}

		public NamespaceDeclarationSyntax[] Namespaces() {
			return namespaces;
		}

		public ClassDeclarationSyntax[] Classes() {
			return classes;
		}

		public EnumDeclarationSyntax[] Enums() {
			return enums;
		}

		public InterfaceDeclarationSyntax[] Interfaces() {
			return interfaces;
		}
	}

	public class UsingDirectiveSyntax {
		private string name;

		public UsingDirectiveSyntax(string inputName) {
			name = inputName;
		}

		public string Name() {
			return name;
		}
	}

	public class NamespaceDeclarationSyntax {
		private string name;
		private ClassDeclarationSyntax[] classes;
		private EnumDeclarationSyntax[] enums;
		private InterfaceDeclarationSyntax[] interfaces;

		public NamespaceDeclarationSyntax( string inputName, ClassDeclarationSyntax[] inputClasses, EnumDeclarationSyntax[] inputEnums, InterfaceDeclarationSyntax[] inputInterfaces ) {
			name = inputName;
			classes = inputClasses;
			enums = inputEnums;
			interfaces = inputInterfaces;
		}

		public string Name() { return name; }

		public ClassDeclarationSyntax[] Classes() { return classes; }

		public EnumDeclarationSyntax[] Enums() { return enums; }

		public InterfaceDeclarationSyntax[] Interfaces() { return interfaces; }
	}

	public class ClassDeclarationSyntax {
		private string name;
		private MethodDeclarationSyntax[] methods;

		public ClassDeclarationSyntax(string inputName, MethodDeclarationSyntax[] inputMethods) {
			name = inputName;
			methods = inputMethods;
		}

		public string Name() { return name; }

		public MethodDeclarationSyntax[] Methods() { return methods; }
	}

	public class MethodDeclarationSyntax {
		private string name;
		private bool isStatic;
		private bool isVirtual;
		private bool isOverride;
		private TypeSyntax returnType;
		private TypeSyntax sizeOfType;
		private ParameterSyntax[] parameters;
		private StatementSyntax body;

		public MethodDeclarationSyntax(string inputName, bool inputIsStatic, bool inputIsVirtual, bool inputIsOverride, TypeSyntax inputReturnType, ParameterSyntax[] inputParameters, StatementSyntax inputBody) {
			name = inputName;
			isStatic = inputIsStatic;
			isVirtual = inputIsVirtual;
			isOverride = inputIsOverride;
			returnType = inputReturnType;
			parameters = inputParameters;
			body = inputBody;
		}

		public string Name() { return name; }

		public bool IsStatic() { return isStatic; }

		public bool IsVirtual() { return isVirtual; }

		public bool IsOverride() { return isOverride; }

		public TypeSyntax ReturnType() { return returnType; }

		public ParameterSyntax[] Parameters() { return parameters; }

		public StatementSyntax Body() { return body; }
	}

	public class InterfaceDeclarationSyntax {
		private string name;
		private MethodDeclarationSyntax[] methods;

		public InterfaceDeclarationSyntax(string inputName, MethodDeclarationSyntax[] inputMethods) {
			name = inputName;
			methods = inputMethods;
		}

		public string Name() {
			return name;
		}

		public MethodDeclarationSyntax[] Methods() {
			return methods;
		}
	}

	public class ParameterSyntax {
		private TypeSyntax type;
		private string name;

		public ParameterSyntax(TypeSyntax inputType, string inputName) {
			type = inputType;
			name = inputName;
		}

		public TypeSyntax Type() { return type; }

		public string Name() { return name; }
	}

	public class TypeSyntax {
		private string displayName;

		public TypeSyntax(string inputDisplayName) {
			displayName = inputDisplayName;
		}

		public string DisplayName() { return displayName; }
	}

	public class StatementSyntax {
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

		private int kind;
		private StatementSyntax[] statements;
		private ExpressionSyntax condition;
		private StatementSyntax thenStatement;
		private StatementSyntax elseStatement;
		private StatementSyntax body;
		private ExpressionSyntax expression;
		private TypeSyntax type;
		private string name;
		private ExpressionSyntax initializer;
		private StatementSyntax catchBlock;
		private TypeSyntax catchType;
		private string catchName;

		public StatementSyntax(int inputKind) {
			kind = inputKind;
		}

		public int Kind() { return kind; }
		public StatementSyntax[] Statements() { return statements; }
		public ExpressionSyntax Condition() { return condition; }
		public StatementSyntax ThenStatement() { return thenStatement; }
		public StatementSyntax ElseStatement() { return elseStatement; }
		public StatementSyntax Body() { return body; }
		public ExpressionSyntax Expression() { return expression; }
		public TypeSyntax Type() { return type; }
		public string Name() { return name; }
		public ExpressionSyntax Initializer() { return initializer; }
		public StatementSyntax CatchBlock() { return catchBlock; }
		public TypeSyntax CatchType() { return catchType; }
		public string CatchName() { return catchName; }

		public static StatementSyntax Block(StatementSyntax[] items) {
			StatementSyntax node = new StatementSyntax(KindBlock());
			node.statements = items;
			return node;
		}

		public static StatementSyntax If(ExpressionSyntax inputCondition, StatementSyntax inputThen, StatementSyntax inputElse) {
			StatementSyntax node = new StatementSyntax(KindIfStatement());
			node.condition = inputCondition;
			node.thenStatement = inputThen;
			node.elseStatement = inputElse;
			return node;
		}

		public static StatementSyntax Return(ExpressionSyntax inputExpression) {
			StatementSyntax node = new StatementSyntax(KindReturnStatement());
			node.expression = inputExpression;
			return node;
		}

		public static StatementSyntax ExpressionStatement(ExpressionSyntax inputExpression) {
			StatementSyntax node = new StatementSyntax(KindExpressionStatement());
			node.expression = inputExpression;
			return node;
		}

		public static StatementSyntax VariableDeclaration(TypeSyntax inputType, string inputName, ExpressionSyntax inputInitializer) {
			StatementSyntax node = new StatementSyntax(KindVariableDeclaration());
			node.type = inputType;
			node.name = inputName;
			node.initializer = inputInitializer;
			return node;
		}

		public static StatementSyntax While(ExpressionSyntax inputCondition, StatementSyntax inputBody) {
			StatementSyntax node = new StatementSyntax(KindWhileStatement());
			node.condition = inputCondition;
			node.body = inputBody;
			return node;
		}

		public static StatementSyntax Break() {
			return new StatementSyntax(KindBreakStatement());
		}

		public static StatementSyntax Continue() {
			return new StatementSyntax(KindContinueStatement());
		}

		public static StatementSyntax Try(StatementSyntax inputBody, TypeSyntax inputCatchType, string inputCatchName, StatementSyntax inputCatchBlock) {
			StatementSyntax node = new StatementSyntax(KindTryStatement());
			node.body = inputBody;
			node.catchType = inputCatchType;
			node.catchName = inputCatchName;
			node.catchBlock = inputCatchBlock;
			return node;
		}

		public static StatementSyntax Throw(ExpressionSyntax inputExpression) {
			StatementSyntax node = new StatementSyntax(KindThrowStatement());
			node.expression = inputExpression;
			return node;
		}
	}

	public class ExpressionSyntax {
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
		private ExpressionSyntax receiver;
		private string memberName;
		private ExpressionSyntax target;
		private ExpressionSyntax[] arguments;
		private ExpressionSyntax value;
		private ExpressionSyntax left;
		private SyntaxKind op;
		private ExpressionSyntax right;
		private ExpressionSyntax index;
		private TypeSyntax type;
		private ExpressionSyntax size;
		private TypeSyntax castType;
		private ExpressionSyntax castExpression;
		private SyntaxKind unaryOp;
		private ExpressionSyntax unaryOperand;
		private TypeSyntax sizeOfType;

		public ExpressionSyntax(int inputKind) {
			kind = inputKind;
		}

		public int Kind() { return kind; }
		public string Name() { return name; }
		public string LiteralKind() { return literalKind; }
		public string LiteralText() { return literalText; }
		public ExpressionSyntax Receiver() { return receiver; }
		public string MemberName() { return memberName; }
		public ExpressionSyntax Target() { return target; }
		public ExpressionSyntax[] Arguments() { return arguments; }
		public ExpressionSyntax Value() { return value; }
		public ExpressionSyntax Left() { return left; }
		public SyntaxKind OperatorKind() { return op; }
		public ExpressionSyntax Right() { return right; }
		public ExpressionSyntax Index() { return index; }
		public TypeSyntax Type() { return type; }
		public ExpressionSyntax Size() { return size; }
		public TypeSyntax CastType() { return castType; }
		public ExpressionSyntax CastExpression() { return castExpression; }
		public SyntaxKind UnaryOperatorKind() { return unaryOp; }
		public ExpressionSyntax UnaryOperand() { return unaryOperand; }
		public TypeSyntax SizeOfType() { return sizeOfType; }

		public static ExpressionSyntax NameExpr(string inputName) {
			ExpressionSyntax node = new ExpressionSyntax(KindName());
			node.name = inputName;
			return node;
		}

		public static ExpressionSyntax Literal(string inputKind, string inputText) {
			ExpressionSyntax node = new ExpressionSyntax(KindLiteral());
			node.literalKind = inputKind;
			node.literalText = inputText;
			return node;
		}

		public static ExpressionSyntax MemberAccess(ExpressionSyntax inputReceiver, string inputMemberName) {
			ExpressionSyntax node = new ExpressionSyntax(KindMemberAccess());
			node.receiver = inputReceiver;
			node.memberName = inputMemberName;
			return node;
		}

		public static ExpressionSyntax Invocation(ExpressionSyntax inputTarget, ExpressionSyntax[] inputArguments) {
			ExpressionSyntax node = new ExpressionSyntax(KindInvocation());
			node.target = inputTarget;
			node.arguments = inputArguments;
			return node;
		}

		public static ExpressionSyntax Assignment(ExpressionSyntax inputTarget, ExpressionSyntax inputValue) {
			ExpressionSyntax node = new ExpressionSyntax(KindAssignment());
			node.target = inputTarget;
			node.value = inputValue;
			return node;
		}

		public static ExpressionSyntax Binary(ExpressionSyntax inputLeft, SyntaxKind inputOp, ExpressionSyntax inputRight) {
			ExpressionSyntax node = new ExpressionSyntax(KindBinary());
			node.left = inputLeft;
			node.op = inputOp;
			node.right = inputRight;
			return node;
		}

		public static ExpressionSyntax IndexExpr(ExpressionSyntax inputReceiver, ExpressionSyntax inputIndex) {
			ExpressionSyntax node = new ExpressionSyntax(KindIndex());
			node.receiver = inputReceiver;
			node.index = inputIndex;
			return node;
		}

		public static ExpressionSyntax ObjectCreation(TypeSyntax inputType) {
			ExpressionSyntax node = new ExpressionSyntax(KindObjectCreation());
			node.type = inputType;
			return node;
		}

		public static ExpressionSyntax ArrayCreation(TypeSyntax inputElementType, ExpressionSyntax inputSize) {
			ExpressionSyntax node = new ExpressionSyntax(KindArrayCreation());
			node.type = inputElementType;
			node.size = inputSize;
			return node;
		}

		public static ExpressionSyntax Cast(TypeSyntax inputType, ExpressionSyntax inputExpression) {
			ExpressionSyntax node = new ExpressionSyntax(KindCast());
			node.castType = inputType;
			node.castExpression = inputExpression;
			return node;
		}

		public static ExpressionSyntax Unary(SyntaxKind inputOp, ExpressionSyntax inputOperand) {
			ExpressionSyntax node = new ExpressionSyntax(KindUnary());
			node.unaryOp = inputOp;
			node.unaryOperand = inputOperand;
			return node;
		}

		public static ExpressionSyntax SizeOf(TypeSyntax inputType) {
			ExpressionSyntax node = new ExpressionSyntax(KindSizeOf());
			node.sizeOfType = inputType;
			return node;
		}
	}

	public class EnumDeclarationSyntax {
		private string name;
		private EnumMemberSyntax[] members;

		public EnumDeclarationSyntax(string inputName, EnumMemberSyntax[] inputMembers) {
			name = inputName;
			members = inputMembers;
		}

		public string Name() {
			return name;
		}

		public EnumMemberSyntax[] Members() {
			return members;
		}
	}

	public class EnumMemberSyntax {
		private string name;
		private int value;
		private bool hasExplicitValue;

		public EnumMemberSyntax(string inputName, int inputValue, bool inputHasExplicitValue) {
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
