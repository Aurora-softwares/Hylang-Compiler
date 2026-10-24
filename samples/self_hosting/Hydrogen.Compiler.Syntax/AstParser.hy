using Hydrogen.Compiler.Diagnostics;

namespace Hydrogen.Compiler.Syntax {
    public class AstParser {
        private Hydrogen.Compiler.Core.BuildProgress buildProgress;

        public void SetBuildProgress(Hydrogen.Compiler.Core.BuildProgress value) {
            buildProgress = value;
        }

        private SyntaxTokenList tokens;
        private DiagnosticBag diagnostics;
        private int index;

        public AstParser(SyntaxTokenList inputTokens, DiagnosticBag inputDiagnostics) {
            tokens = inputTokens;
            diagnostics = inputDiagnostics;
            index = 0;
        }

        public CompilationUnitSyntax ParseCompilationUnit() {
            UsingDirectiveSyntax[] usings = ParseUsingDirectives();
            NamespaceDeclarationSyntax[] namespaces = new NamespaceDeclarationSyntax[0];
            int namespaceCount = 0;
            ClassDeclarationSyntax[] classes = new ClassDeclarationSyntax[0];
            int classCount = 0;
			EnumDeclarationSyntax[] enums = new EnumDeclarationSyntax[0];
			int enumCount = 0;
			InterfaceDeclarationSyntax[] interfaces = new InterfaceDeclarationSyntax[0];
			int interfaceCount = 0;

            while (!Check(SyntaxKind.EndOfFileToken)) {
                SkipModifiers();
                if (Check(SyntaxKind.NamespaceKeyword)) {
                    namespaces = AppendNamespace(namespaces, namespaceCount, ParseNamespace());
                    namespaceCount = namespaceCount + 1;
                    continue;
                }
                if (Check(SyntaxKind.ClassKeyword) || Check(SyntaxKind.StructKeyword)) {
                    classes = AppendClass(classes, classCount, ParseClass());
                    classCount = classCount + 1;
                    continue;
                }
				if (Check(SyntaxKind.EnumKeyword)) {
					enums = AppendEnum(enums, enumCount, ParseEnum());
					enumCount = enumCount + 1;
					continue;
				}
				if (Check(SyntaxKind.InterfaceKeyword)) {
					interfaces = AppendInterface(interfaces, interfaceCount, ParseInterface());
					interfaceCount = interfaceCount + 1;
					continue;
				}

                diagnostics.Report(Current().Line(), Current().Column(), "Expected namespace or class declaration");
                Advance();
            }
            Consume(SyntaxKind.EndOfFileToken, "Expected end of file");
            return new CompilationUnitSyntax(usings, namespaces, classes, enums, interfaces);
        }

        private UsingDirectiveSyntax[] ParseUsingDirectives() {
            UsingDirectiveSyntax[] items = new UsingDirectiveSyntax[0];
            int count = 0;
            while (Check(SyntaxKind.UsingKeyword)) {
                Consume(SyntaxKind.UsingKeyword, "Expected using");
                string name = ParseQualifiedNameText();
                Consume(SyntaxKind.SemicolonToken, "Expected ';' after using");
                items = AppendUsing(items, count, new UsingDirectiveSyntax(name));
                count = count + 1;
            }
            return items;
        }

        private NamespaceDeclarationSyntax ParseNamespace() {
            Consume(SyntaxKind.NamespaceKeyword, "Expected namespace");
            string name = ParseQualifiedNameText();
            Consume(SyntaxKind.OpenBraceToken, "Expected '{' after namespace");
            ClassDeclarationSyntax[] classes = new ClassDeclarationSyntax[0];
            int classCount = 0;
			EnumDeclarationSyntax[] enums = new EnumDeclarationSyntax[0];
			int enumCount = 0;
			InterfaceDeclarationSyntax[] interfaces = new InterfaceDeclarationSyntax[0];
			int interfaceCount = 0;

            while (!Check(SyntaxKind.CloseBraceToken) && !Check(SyntaxKind.EndOfFileToken)) {
                SkipModifiers();
                if (Check(SyntaxKind.ClassKeyword) || Check(SyntaxKind.StructKeyword)) {
                    classes = AppendClass(classes, classCount, ParseClass());
                    classCount = classCount + 1;
                    continue;
                }
				if (Check(SyntaxKind.EnumKeyword)) {
					enums = AppendEnum(enums, enumCount, ParseEnum());
					enumCount = enumCount + 1;
					continue;
				}
				if (Check(SyntaxKind.InterfaceKeyword)) {
					interfaces = AppendInterface(interfaces, interfaceCount, ParseInterface());
					interfaceCount = interfaceCount + 1;
					continue;
				}
                diagnostics.Report(Current().Line(), Current().Column(), "Expected class declaration");
                Advance();
            }
            Consume(SyntaxKind.CloseBraceToken, "Expected '}' after namespace");
            return new NamespaceDeclarationSyntax(name, classes, enums, interfaces);
        }

        private ClassDeclarationSyntax ParseClass() {
            bool isStruct = false;
            if (Check(SyntaxKind.ClassKeyword)) {
                Consume(SyntaxKind.ClassKeyword, "Expected class");
            } else {
                isStruct = true;
                Consume(SyntaxKind.StructKeyword, "Expected struct");
            }
            string name = ConsumeIdentifier("Expected class name");
            string baseType = ""; string[] declaredBases = new string[0]; int baseCount = 0;
            // Skip base list / type parameters in stage1 AST (subset avoids them).
            if (Check(SyntaxKind.LessToken)) {
                diagnostics.Report(Current().Line(), Current().Column(), "not supported in self-host subset: generics");
                SkipTypeArgumentOrParameterList();
            }
            if (Check(SyntaxKind.ColonToken)) {
                Advance();
                while (true) {
                    string declaredBase = ParseQualifiedNameText();
                    declaredBases = AppendString(declaredBases, baseCount, declaredBase); baseCount = baseCount + 1;
                    if (!Check(SyntaxKind.CommaToken)) { break; }
                    Advance();
                }
                if (declaredBases.Length > 0) { baseType = declaredBases[0]; }
            }
            Consume(SyntaxKind.OpenBraceToken, "Expected '{' after class");
            ClassMemberListSyntax members = ParseClassMembers();
            Consume(SyntaxKind.CloseBraceToken, "Expected '}' after class");
            ClassDeclarationSyntax result = new ClassDeclarationSyntax(name, members.Fields(), members.Methods());
            result.SetStruct(isStruct);
            result.SetBaseType(baseType);
            result.SetDeclaredBases(declaredBases);
            return result;
        }

        private ClassMemberListSyntax ParseClassMembers() {
            FieldDeclarationSyntax[] fields = new FieldDeclarationSyntax[0];
            int fieldCount = 0;
            MethodDeclarationSyntax[] methods = new MethodDeclarationSyntax[0];
            int methodCount = 0;
            int previousIndex = -1;
            while (!Check(SyntaxKind.CloseBraceToken) && !Check(SyntaxKind.EndOfFileToken)) {
                bool isStatic = false;
                bool isPrivate = false;
				bool isVirtual = false;
				bool isOverride = false;

                if (index == previousIndex) {
                    diagnostics.Report(
                        Current().Line(),
                        Current().Column(),
                        "parser made no progress in class members");

                    Advance();
                    continue;
                }

                previousIndex = index;

				while (SyntaxFacts.IsModifier(Current().Kind())) {
                    if (Current().Kind() == SyntaxKind.PrivateKeyword) { isPrivate = true; }
					if (Current().Kind() == SyntaxKind.StaticKeyword) {
						isStatic = true;
					}
					if (Current().Kind() == SyntaxKind.VirtualKeyword) {
						isVirtual = true;
					}
					if (Current().Kind() == SyntaxKind.OverrideKeyword) {
						isOverride = true;
					}
					Advance();
				}

                TypeSyntax returnType = ParseType();
                string name = "";
                if (Check(SyntaxKind.IdentifierToken)) {
                    name = ConsumeIdentifier("Expected member name");
                    if (Check(SyntaxKind.OpenParenToken)) {
                        ParameterSyntax[] parameters = ParseParameterList();
                        StatementSyntax body = ParseBlock();
                        methods = AppendMethod(methods, methodCount, new MethodDeclarationSyntax(name, isStatic, isVirtual, isOverride, returnType, parameters, body));
                        methods[methodCount].SetPrivate(isPrivate);
                        methodCount = methodCount + 1;
                        continue;
                    }
                } else if (Check(SyntaxKind.OpenParenToken)) {
                    // Constructor: no explicit return type. Treat as void-returning method named after the type.
                    ParameterSyntax[] parameters2 = ParseParameterList();
                    string initializerKind = "";
                    ExpressionSyntax[] initializerArguments = new ExpressionSyntax[0];
                    if (Check(SyntaxKind.ColonToken)) {
                        Advance();
                        if (Check(SyntaxKind.BaseKeyword)) { initializerKind = "base"; Advance(); }
                        else if (Check(SyntaxKind.ThisKeyword)) { initializerKind = "this"; Advance(); }
                        else { diagnostics.Report(Current().Line(), Current().Column(), "Expected base or this constructor initializer"); Advance(); }
                        initializerArguments = ParseArgumentList();
                    }
                    StatementSyntax body2 = ParseBlock();
                    methods = AppendMethod(methods, methodCount, new MethodDeclarationSyntax(returnType.DisplayName(), false, false, false, new TypeSyntax("void"), parameters2, body2));
                    methods[methodCount].SetPrivate(isPrivate);
                    methods[methodCount].SetConstructorInitializer(initializerKind, initializerArguments);
                    methodCount = methodCount + 1;
                    continue;
                } else {
                    Consume(SyntaxKind.IdentifierToken, "Expected member name");
                }

                ExpressionSyntax initializer = null;
                if (Check(SyntaxKind.EqualsToken)) {
                    Advance();
                    initializer = ParseExpression();
                }
                Consume(SyntaxKind.SemicolonToken, "Expected ';' after field");
				fields = AppendField(fields, fieldCount, new FieldDeclarationSyntax(returnType, name, isStatic, initializer));
				fields[fieldCount].SetPrivate(isPrivate);
                fieldCount = fieldCount + 1;
            }
            return new ClassMemberListSyntax(fields, methods);
        }

		private EnumDeclarationSyntax ParseEnum() {
			Consume(SyntaxKind.EnumKeyword, "Expected enum");
			string name = ConsumeIdentifier("Expected enum name");

			Consume(SyntaxKind.OpenBraceToken, "Expected '{' after enum name");

			EnumMemberSyntax[] members = new EnumMemberSyntax[0];
			int count = 0;
			int nextValue = 0;

			while (!Check(SyntaxKind.CloseBraceToken) && !Check(SyntaxKind.EndOfFileToken)) {
				string memberName = ConsumeIdentifier("Expected enum member name");

				int value = nextValue;
				bool hasExplicitValue = false;

				if (Check(SyntaxKind.EqualsToken)) {
					Advance();

					if (Check(SyntaxKind.NumberToken)) {
						value = ParseDecimalIntLiteral(Current());
						hasExplicitValue = true;
						Advance();
					} else {
						diagnostics.Report(Current().Line(), Current().Column(), "Expected numeric enum value");
					}
				}

				members = AppendEnumMember(members, count, new EnumMemberSyntax(memberName, value, hasExplicitValue));
				count = count + 1;
				nextValue = value + 1;

				if (Check(SyntaxKind.CommaToken)) {
					Advance();
					continue;
				}

				if (!Check(SyntaxKind.CloseBraceToken)) {
					diagnostics.Report(Current().Line(), Current().Column(), "Expected ',' or '}' after enum member");
					Advance();
				}
			}

			Consume(SyntaxKind.CloseBraceToken, "Expected '}' after enum");
			return new EnumDeclarationSyntax(name, members);
		}

		private InterfaceDeclarationSyntax ParseInterface() {
			Consume(SyntaxKind.InterfaceKeyword, "Expected interface");
			string name = ConsumeIdentifier("Expected interface name");
			string[] declaredBases = new string[0]; int baseCount = 0;
			if (Check(SyntaxKind.ColonToken)) {
				Advance();
				while (true) {
					declaredBases = AppendString(declaredBases, baseCount, ParseQualifiedNameText()); baseCount = baseCount + 1;
					if (!Check(SyntaxKind.CommaToken)) { break; }
					Advance();
				}
			}

			Consume(SyntaxKind.OpenBraceToken, "Expected '{' after interface name");

			MethodDeclarationSyntax[] methods = new MethodDeclarationSyntax[0];
			int count = 0;

			while (!Check(SyntaxKind.CloseBraceToken) && !Check(SyntaxKind.EndOfFileToken)) {
				SkipModifiers();

				TypeSyntax returnType = ParseType();
				string methodName = ConsumeIdentifier("Expected interface method name");
				ParameterSyntax[] parameters = ParseParameterList();

				Consume(SyntaxKind.SemicolonToken, "Expected ';' after interface method");

				methods = AppendMethod(
					methods,
					count,
					new MethodDeclarationSyntax(methodName, false, false, false, returnType, parameters, null)
				);
				count = count + 1;
			}

			Consume(SyntaxKind.CloseBraceToken, "Expected '}' after interface");
			InterfaceDeclarationSyntax result = new InterfaceDeclarationSyntax(name, methods);
			result.SetDeclaredBases(declaredBases); return result;
		}

        private ParameterSyntax[] ParseParameterList() {
            Consume(SyntaxKind.OpenParenToken, "Expected '('");
            ParameterSyntax[] items = new ParameterSyntax[0];
            int count = 0;
            if (!Check(SyntaxKind.CloseParenToken)) {
                while (true) {
                    TypeSyntax type = ParseType();
                    string name = ConsumeIdentifier("Expected parameter name");
                    items = AppendParameter(items, count, new ParameterSyntax(type, name));
                    count = count + 1;
                    if (Check(SyntaxKind.CommaToken)) {
                        Advance();
                        continue;
                    }
                    break;
                }
            }
            Consume(SyntaxKind.CloseParenToken, "Expected ')'");
            return items;
        }

        private StatementSyntax ParseBlock() {
            Consume(SyntaxKind.OpenBraceToken, "Expected '{'");
            StatementSyntax[] items = new StatementSyntax[0];
            int count = 0;
            while (!Check(SyntaxKind.CloseBraceToken) && !Check(SyntaxKind.EndOfFileToken)) {
                StatementSyntax statement = ParseStatement();
                items = AppendStatement(items, count, statement);
                count = count + 1;
            }
            Consume(SyntaxKind.CloseBraceToken, "Expected '}'");
            return StatementSyntax.Block(items);
        }

        private StatementSyntax ParseStatement() {
            SyntaxToken start = Current();
            StatementSyntax result = ParseStatementCore();
            SyntaxToken end = Previous();
            result.SetLocation(start.Line(), start.Column(), start.Position(), SpanLength(start, end));
            return result;
        }

        private StatementSyntax ParseStatementCore() {
            if (Check(SyntaxKind.OpenBraceToken)) {
                return ParseBlock();
            }
            if (Check(SyntaxKind.IfKeyword)) {
                return ParseIf();
            }
            if (Check(SyntaxKind.WhileKeyword)) {
                return ParseWhile();
            }
            if (Check(SyntaxKind.ForKeyword)) {
                return ParseFor();
            }
            if (Check(SyntaxKind.ForeachKeyword)) {
                return ParseForeach();
            }
            if (Check(SyntaxKind.ReturnKeyword)) {
                return ParseReturn();
            }
			if (Check(SyntaxKind.TryKeyword)) {
				return ParseTry();
			}
			if (Check(SyntaxKind.ThrowKeyword)) {
				return ParseThrow();
			}
			if (Check(SyntaxKind.BreakKeyword)) {
				Advance();
				Consume(SyntaxKind.SemicolonToken, "Expected ';' after break");
				return StatementSyntax.Break();
			}
			if (Check(SyntaxKind.ContinueKeyword)) {
				Advance();
				Consume(SyntaxKind.SemicolonToken, "Expected ';' after continue");
				return StatementSyntax.Continue();
			}
			if (Check(SyntaxKind.UnsafeKeyword)) {
				Advance();
				return ParseBlock();
			}

            // local declaration: <type|var> <id> [= expr] ;
            if (LooksLikeLocalDeclaration()) {
                TypeSyntax type = ParseType();
                string name = ConsumeIdentifier("Expected identifier after type");
                ExpressionSyntax initializer = null;
                if (Check(SyntaxKind.EqualsToken)) {
                    Advance();
                    initializer = ParseExpression();
                }
                Consume(SyntaxKind.SemicolonToken, "Expected ';' after declaration");
                return StatementSyntax.VariableDeclaration(type, name, initializer);
            }

            ExpressionSyntax expr = ParseExpression();
            Consume(SyntaxKind.SemicolonToken, "Expected ';' after expression");
            return StatementSyntax.ExpressionStatement(expr);
        }

        private bool LooksLikeLocalDeclaration() {
            // We only treat a statement as a declaration if a type-like sequence is followed by an identifier.
            int offset = 0;
            SyntaxKind kind = Peek(offset).Kind();
            if (!IsTypeStart(kind)) {
                return false;
            }

            // consume type start
            offset = offset + 1;

            // qualified name segments
            while (Peek(offset).Kind() == SyntaxKind.DotToken) {
                if (Peek(offset + 1).Kind() != SyntaxKind.IdentifierToken) {
                    return false;
                }
                offset = offset + 2;
            }

            // optional array brackets
            if (Peek(offset).Kind() == SyntaxKind.OpenBracketToken && Peek(offset + 1).Kind() == SyntaxKind.CloseBracketToken) {
                offset = offset + 2;
            }

            // now must be an identifier (the variable name)
            return Peek(offset).Kind() == SyntaxKind.IdentifierToken;
        }

        private StatementSyntax ParseIf() {
            Consume(SyntaxKind.IfKeyword, "Expected if");
            Consume(SyntaxKind.OpenParenToken, "Expected '(' after if");
            ExpressionSyntax condition = ParseExpression();
            Consume(SyntaxKind.CloseParenToken, "Expected ')' after if condition");
            StatementSyntax thenStatement = ParseStatement();
            StatementSyntax elseStatement = null;
            if (Check(SyntaxKind.ElseKeyword)) {
                Advance();
                elseStatement = ParseStatement();
            }
            return StatementSyntax.If(condition, thenStatement, elseStatement);
        }

        private StatementSyntax ParseWhile() {
            Consume(SyntaxKind.WhileKeyword, "Expected while");
            Consume(SyntaxKind.OpenParenToken, "Expected '(' after while");
            ExpressionSyntax condition = ParseExpression();
            Consume(SyntaxKind.CloseParenToken, "Expected ')' after while condition");
            StatementSyntax body = ParseStatement();
            return StatementSyntax.While(condition, body);
        }

        private StatementSyntax ParseFor() {
            Consume(SyntaxKind.ForKeyword, "Expected for");
            Consume(SyntaxKind.OpenParenToken, "Expected '(' after for");

            StatementSyntax initializer = null;
            if (Check(SyntaxKind.SemicolonToken)) {
                Advance();
            } else if (LooksLikeLocalDeclaration()) {
                TypeSyntax type = ParseType();
                string name = ConsumeIdentifier("Expected identifier after type");
                ExpressionSyntax value = null;
                if (Check(SyntaxKind.EqualsToken)) {
                    Advance();
                    value = ParseExpression();
                }
                Consume(SyntaxKind.SemicolonToken, "Expected ';' after for initializer");
                initializer = StatementSyntax.VariableDeclaration(type, name, value);
            } else {
                initializer = StatementSyntax.ExpressionStatement(ParseExpression());
                Consume(SyntaxKind.SemicolonToken, "Expected ';' after for initializer");
            }

            ExpressionSyntax condition = ExpressionSyntax.Literal("bool", "true");
            if (!Check(SyntaxKind.SemicolonToken)) {
                condition = ParseExpression();
            }
            Consume(SyntaxKind.SemicolonToken, "Expected ';' after for condition");

            ExpressionSyntax increment = null;
            if (!Check(SyntaxKind.CloseParenToken)) {
                increment = ParseExpression();
            }
            Consume(SyntaxKind.CloseParenToken, "Expected ')' after for clauses");
            return StatementSyntax.For(initializer, condition, increment, ParseStatement());
        }

        private StatementSyntax ParseForeach() {
            Consume(SyntaxKind.ForeachKeyword, "Expected foreach");
            Consume(SyntaxKind.OpenParenToken, "Expected '(' after foreach");
            TypeSyntax elementType = ParseType();
            string elementName = ConsumeIdentifier("Expected foreach variable name");
            Consume(SyntaxKind.InKeyword, "Expected 'in' after foreach variable");
            ExpressionSyntax collection = ParseExpression();
            Consume(SyntaxKind.CloseParenToken, "Expected ')' after foreach collection");
            StatementSyntax body = ParseStatement();

            string collectionName = "__hy_foreach$collection";
            string indexName = "__hy_foreach$index";
            StatementSyntax collectionVariable = StatementSyntax.VariableDeclaration(new TypeSyntax("var"), collectionName, collection);
            StatementSyntax indexVariable = StatementSyntax.VariableDeclaration(new TypeSyntax("int"), indexName,
                ExpressionSyntax.Literal("number", "0"));
            ExpressionSyntax length = ExpressionSyntax.MemberAccess(ExpressionSyntax.NameExpr(collectionName), "Length");
            ExpressionSyntax condition = ExpressionSyntax.Binary(ExpressionSyntax.NameExpr(indexName), SyntaxKind.LessToken, length);
            ExpressionSyntax increment = ExpressionSyntax.Assignment(ExpressionSyntax.NameExpr(indexName), SyntaxKind.PlusEqualsToken,
                ExpressionSyntax.Literal("number", "1"));
            ExpressionSyntax item = ExpressionSyntax.IndexExpr(ExpressionSyntax.NameExpr(collectionName), ExpressionSyntax.NameExpr(indexName));
            StatementSyntax iterationVariable = StatementSyntax.VariableDeclaration(elementType, elementName, item);
            StatementSyntax[] bodyStatements = new StatementSyntax[2];
            bodyStatements[0] = iterationVariable;
            bodyStatements[1] = body;
            StatementSyntax loop = StatementSyntax.For(indexVariable, condition, increment, StatementSyntax.Block(bodyStatements));
            StatementSyntax[] outerStatements = new StatementSyntax[2];
            outerStatements[0] = collectionVariable;
            outerStatements[1] = loop;
            return StatementSyntax.Block(outerStatements);
        }

        private StatementSyntax ParseReturn() {
            Consume(SyntaxKind.ReturnKeyword, "Expected return");
            ExpressionSyntax expression = null;
            if (!Check(SyntaxKind.SemicolonToken)) {
                expression = ParseExpression();
            }
            Consume(SyntaxKind.SemicolonToken, "Expected ';' after return");
            return StatementSyntax.Return(expression);
        }

		private StatementSyntax ParseTry() {
			Consume(SyntaxKind.TryKeyword, "Expected try");
			StatementSyntax tryBlock = ParseBlock();
			Consume(SyntaxKind.CatchKeyword, "Expected catch after try block");

			TypeSyntax catchType = new TypeSyntax("string");
			string catchName = "";
			if (Check(SyntaxKind.OpenParenToken)) {
				Advance();
				catchType = ParseType();
				catchName = ConsumeIdentifier("Expected catch variable name");
				Consume(SyntaxKind.CloseParenToken, "Expected ')' after catch clause");
			}

			StatementSyntax catchBlock = ParseBlock();
			return StatementSyntax.Try(tryBlock, catchType, catchName, catchBlock);
		}

		private StatementSyntax ParseThrow() {
			Consume(SyntaxKind.ThrowKeyword, "Expected throw");
			ExpressionSyntax expression = null;
			if (!Check(SyntaxKind.SemicolonToken)) {
				expression = ParseExpression();
			} else {
				diagnostics.Report(Current().Line(), Current().Column(), "Expected expression after throw");
			}
			Consume(SyntaxKind.SemicolonToken, "Expected ';' after throw");
			return StatementSyntax.Throw(expression);
		}

        private ExpressionSyntax ParseExpression() {
            SyntaxToken start = Current();
            ExpressionSyntax result = ParseAssignment();
            SyntaxToken end = Previous();
            result.SetLocation(start.Line(), start.Column(), start.Position(), SpanLength(start, end));
            return result;
        }

        private ExpressionSyntax ParseAssignment() {
            ExpressionSyntax left = ParseConditional();
            if (ShiftLeftAssignmentPair() || ShiftRightAssignmentPair()) {
                bool leftShift = ShiftLeftAssignmentPair();
                Advance(); Advance();
                SyntaxKind op = SyntaxKind.ShiftRightEqualsToken;
                if (leftShift) { op = SyntaxKind.ShiftLeftEqualsToken; }
                return ExpressionSyntax.Assignment(left, op, ParseAssignment());
            }
            if (IsAssignmentToken(Current().Kind())) {
                SyntaxKind op = Advance().Kind();
                ExpressionSyntax right = ParseAssignment();
                return ExpressionSyntax.Assignment(left, op, right);
            }
            return left;
        }

        private ExpressionSyntax ParseConditional() {
            ExpressionSyntax condition = ParseCoalesce();
            if (!Check(SyntaxKind.QuestionToken)) { return condition; }
            Advance();
            ExpressionSyntax whenTrue = ParseExpression();
            Consume(SyntaxKind.ColonToken, "Expected ':' in conditional expression");
            ExpressionSyntax whenFalse = ParseConditional();
            return ExpressionSyntax.Conditional(condition, whenTrue, whenFalse);
        }

        private ExpressionSyntax ParseCoalesce() {
            ExpressionSyntax left = ParseBinaryExpression(0);
            if (!Check(SyntaxKind.QuestionQuestionToken)) { return left; }
            SyntaxKind op = Advance().Kind();
            return ExpressionSyntax.Binary(left, op, ParseCoalesce());
        }

        private bool ShiftLeftAssignmentPair() {
            return Current().Kind() == SyntaxKind.LessToken && Peek(1).Kind() == SyntaxKind.LessEqualsToken &&
                   Current().Line() == Peek(1).Line() && Current().Column() + 1 == Peek(1).Column();
        }

        private bool ShiftRightAssignmentPair() {
            return Current().Kind() == SyntaxKind.GreaterToken && Peek(1).Kind() == SyntaxKind.GreaterEqualsToken &&
                   Current().Line() == Peek(1).Line() && Current().Column() + 1 == Peek(1).Column();
        }

        private bool IsAssignmentToken(SyntaxKind kind) {
            return kind == SyntaxKind.EqualsToken || kind == SyntaxKind.PlusEqualsToken ||
                kind == SyntaxKind.MinusEqualsToken || kind == SyntaxKind.StarEqualsToken ||
                kind == SyntaxKind.SlashEqualsToken || kind == SyntaxKind.PercentEqualsToken ||
                kind == SyntaxKind.AmpersandEqualsToken || kind == SyntaxKind.PipeEqualsToken ||
                kind == SyntaxKind.CaretEqualsToken;
        }

        private ExpressionSyntax ParseBinaryExpression(int parentPrecedence) {
            ExpressionSyntax left = ParseUnary();
            while (true) {
                if (ShiftLeftAssignmentPair() || ShiftRightAssignmentPair()) { break; }
                bool shiftLeft = ShiftLeftPair();
                bool shiftRight = ShiftRightPair();
                int precedence = BinaryPrecedence(Current().Kind());
                if (shiftLeft || shiftRight) { precedence = 9; }
                if (precedence == 0 || precedence <= parentPrecedence) {
                    break;
                }
                SyntaxKind op = Current().Kind();
                Advance();
                if (shiftLeft || shiftRight) {
                    Advance();
                    if (shiftLeft) { op = SyntaxKind.ShiftLeftToken; }
                    else { op = SyntaxKind.ShiftRightToken; }
                }
                ExpressionSyntax right = ParseBinaryExpression(precedence);
                left = ExpressionSyntax.Binary(left, op, right);
            }
            return left;
        }

        private bool ShiftLeftPair() {
            return Current().Kind() == SyntaxKind.LessToken && Peek(1).Kind() == SyntaxKind.LessToken &&
                   Current().Line() == Peek(1).Line() && Current().Column() + 1 == Peek(1).Column();
        }

        private bool ShiftRightPair() {
            return Current().Kind() == SyntaxKind.GreaterToken && Peek(1).Kind() == SyntaxKind.GreaterToken &&
                   Current().Line() == Peek(1).Line() && Current().Column() + 1 == Peek(1).Column();
        }

        private ExpressionSyntax ParseUnary() {
            if (Check(SyntaxKind.PlusPlusToken) || Check(SyntaxKind.MinusMinusToken)) {
                SyntaxKind op = Advance().Kind();
                return MakeUpdate(ParseUnary(), op, false);
            }
            if (Check(SyntaxKind.OpenParenToken) && LooksLikeCastExpression()) {
                Advance();
                TypeSyntax type = ParseType();
                Consume(SyntaxKind.CloseParenToken, "Expected ')'");
                return ExpressionSyntax.Cast(type, ParseUnary());
            }
            if (Check(SyntaxKind.BangToken) || Check(SyntaxKind.TildeToken) ||
                Check(SyntaxKind.MinusToken) || Check(SyntaxKind.PlusToken)) {
                SyntaxKind op = Advance().Kind();
                ExpressionSyntax operand = ParseUnary();
                return ExpressionSyntax.Unary(op, operand);
            }
            return ParsePostfix();
        }

        private ExpressionSyntax ParsePostfix() {
            ExpressionSyntax expr = ParsePrimary();
            while (true) {
                if (Check(SyntaxKind.DotToken) || (Check(SyntaxKind.QuestionToken) && Peek(1).Kind() == SyntaxKind.DotToken)) {
                    bool conditional = Check(SyntaxKind.QuestionToken);
                    if (conditional) { Advance(); }
                    Advance();
                    string name = ConsumeIdentifier("Expected member name");
                    expr = ExpressionSyntax.MemberAccess(expr, name);
                    expr.SetNullConditional(conditional);
                    continue;
                }
                if (Check(SyntaxKind.OpenParenToken)) {
                    ExpressionSyntax[] args = ParseArgumentList();
                    expr = ExpressionSyntax.Invocation(expr, args);
                    continue;
                }
                if (Check(SyntaxKind.OpenBracketToken) || (Check(SyntaxKind.QuestionToken) && Peek(1).Kind() == SyntaxKind.OpenBracketToken)) {
                    bool conditional = Check(SyntaxKind.QuestionToken);
                    if (conditional) { Advance(); }
                    Advance();
                    ExpressionSyntax indexExpr = ParseExpression();
                    Consume(SyntaxKind.CloseBracketToken, "Expected ']'");
                    expr = ExpressionSyntax.IndexExpr(expr, indexExpr);
                    expr.SetNullConditional(conditional);
                    continue;
                }
                if (Check(SyntaxKind.PlusPlusToken) || Check(SyntaxKind.MinusMinusToken)) {
                    SyntaxKind op = Advance().Kind();
                    expr = MakeUpdate(expr, op, true);
                    continue;
                }
                break;
            }
            return expr;
        }

        private ExpressionSyntax MakeUpdate(ExpressionSyntax target, SyntaxKind op, bool returnsOld) {
            SyntaxKind assignment = SyntaxKind.MinusEqualsToken;
            if (op == SyntaxKind.PlusPlusToken) { assignment = SyntaxKind.PlusEqualsToken; }
            ExpressionSyntax result = ExpressionSyntax.Assignment(target, assignment, ExpressionSyntax.Literal("number", "1"));
            result.SetReturnsOld(returnsOld);
            return result;
        }

        private ExpressionSyntax[] ParseArgumentList() {
            Consume(SyntaxKind.OpenParenToken, "Expected '('");
            ExpressionSyntax[] items = new ExpressionSyntax[0];
            int count = 0;
            if (!Check(SyntaxKind.CloseParenToken)) {
                while (true) {
                    ExpressionSyntax arg = ParseExpression();
                    items = AppendExpression(items, count, arg);
                    count = count + 1;
                    if (Check(SyntaxKind.CommaToken)) {
                        Advance();
                        continue;
                    }
                    break;
                }
            }
            Consume(SyntaxKind.CloseParenToken, "Expected ')'");
            return items;
        }

        private ExpressionSyntax ParsePrimary() {
            if (Check(SyntaxKind.OpenParenToken)) {
                Advance();
                ExpressionSyntax inner = ParseExpression();
                Consume(SyntaxKind.CloseParenToken, "Expected ')'");
                return inner;
            }
            if (Check(SyntaxKind.StringToken)) {
                string tokenText = Advance().Text();
                string text = UnquoteStringToken(tokenText);
                return ExpressionSyntax.Literal("string", text);
            }
            if (Check(SyntaxKind.NumberToken)) {
                string text = Advance().Text();
                return ExpressionSyntax.Literal("number", text);
            }
            if (Check(SyntaxKind.TrueKeyword)) {
                Advance();
                return ExpressionSyntax.Literal("bool", "true");
            }
            if (Check(SyntaxKind.FalseKeyword)) {
                Advance();
                return ExpressionSyntax.Literal("bool", "false");
            }
            if (Check(SyntaxKind.NullKeyword)) {
                Advance();
                return ExpressionSyntax.Literal("null", "null");
            }
            if (Check(SyntaxKind.NewKeyword)) {
                Advance();
                TypeSyntax type = ParseType();
                if (Check(SyntaxKind.OpenBracketToken)) {
                    Advance();
                    ExpressionSyntax size = ParseExpression();
                    Consume(SyntaxKind.CloseBracketToken, "Expected ']'");
                    return ExpressionSyntax.ArrayCreation(type, size);
                }
                // Allow constructor arguments (Stage1B parser support). Binder/codegen may still restrict semantics.
                ExpressionSyntax[] ctorArgs = ParseArgumentList();
                return ExpressionSyntax.ObjectCreation(type, ctorArgs);
            }
			if (Check(SyntaxKind.SizeOfKeyword)) {
				Advance();
				Consume(SyntaxKind.OpenParenToken, "Expected '(' after sizeof");
				TypeSyntax type = ParseType();
				Consume(SyntaxKind.CloseParenToken, "Expected ')' after sizeof type");
				return ExpressionSyntax.SizeOf(type);
			}
            if (Current().Kind() == SyntaxKind.IdentifierToken || Check(SyntaxKind.ThisKeyword) || Check(SyntaxKind.BaseKeyword)) {
                return ExpressionSyntax.NameExpr(Advance().Text());
            }
			if (Check(SyntaxKind.StackAllocKeyword)) {
				Advance();

				TypeSyntax type = ParseType();

				Consume(SyntaxKind.OpenBracketToken, "Expected '[' after stackalloc type");
				ExpressionSyntax size = ParseExpression();
				Consume(SyntaxKind.CloseBracketToken, "Expected ']'");

				return ExpressionSyntax.ArrayCreation(type, size);
			}

            diagnostics.Report(Current().Line(), Current().Column(), "Expected expression");
            // Ensure we always make progress to avoid infinite loops on unexpected tokens.
            Advance();
            return ExpressionSyntax.NameExpr("");
        }

        private bool LooksLikeCastExpression() {
            // Heuristic: ( <type> ) <primary-start>
            if (Peek(0).Kind() != SyntaxKind.OpenParenToken) { return false; }
            if (!IsTypeStart(Peek(1).Kind())) { return false; }

            // Find the closing paren after a simple type (qualified name + optional [] only).
            int offset = 1;
            // consume qualified name / predefined type
            offset = offset + 1;
            while (Peek(offset).Kind() == SyntaxKind.DotToken && Peek(offset + 1).Kind() == SyntaxKind.IdentifierToken) {
                offset = offset + 2;
            }
            if (Peek(offset).Kind() == SyntaxKind.OpenBracketToken && Peek(offset + 1).Kind() == SyntaxKind.CloseBracketToken) {
                offset = offset + 2;
            }
            if (Peek(offset).Kind() != SyntaxKind.CloseParenToken) { return false; }

            SyntaxKind next = Peek(offset + 1).Kind();
            return next == SyntaxKind.IdentifierToken ||
                   next == SyntaxKind.StringToken ||
                   next == SyntaxKind.NumberToken ||
                   next == SyntaxKind.TrueKeyword ||
                   next == SyntaxKind.FalseKeyword ||
                   next == SyntaxKind.NullKeyword ||
                   next == SyntaxKind.NewKeyword ||
                   next == SyntaxKind.SizeOfKeyword ||
                   next == SyntaxKind.BangToken ||
                   next == SyntaxKind.TildeToken ||
                   next == SyntaxKind.MinusToken ||
                   next == SyntaxKind.PlusToken ||
                   next == SyntaxKind.OpenParenToken;
        }

        private string UnquoteStringToken(string tokenText) {
            string result = "";
            int i = 1;
            while (i < tokenText.Length - 1) {
                string ch = tokenText[i];
                if (ch == "\\") {
                    i = i + 1;
                    if (i >= tokenText.Length - 1) { break; }
                    string escaped = tokenText[i];
                    if (escaped == "n") { ch = "\n"; }
                    else if (escaped == "r") { ch = "\r"; }
                    else if (escaped == "t") { ch = "\t"; }
                    else if (escaped == "\\") { ch = "\\"; }
                    else if (escaped == "\"") { ch = "\""; }
                    else { diagnostics.Report(Current().Line(), Current().Column(), "Unsupported string escape"); }
                }
                result = result + ch;
                i = i + 1;
            }
            return result;
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

        private TypeSyntax ParseType() {
            SyntaxToken start = Current();
            string name = "";
            if (IsPredefinedType(Current().Kind())) {
                name = Advance().Text();
            } else {
                name = ParseQualifiedNameText();
            }

            // Array type suffix: only consume empty brackets `[]` (not `[...]` which is array creation).
            while (Check(SyntaxKind.OpenBracketToken) && Peek(1).Kind() == SyntaxKind.CloseBracketToken) {
                Advance();
                Advance();
                name = name + "[]";
            }
            TypeSyntax result = new TypeSyntax(name);
            SyntaxToken end = Previous();
            result.SetLocation(start.Line(), start.Column(), start.Position(), SpanLength(start, end));
            return result;
        }

        private bool IsPredefinedType(SyntaxKind kind) {
            return kind == SyntaxKind.VoidKeyword ||
                   kind == SyntaxKind.BoolKeyword ||
                   kind == SyntaxKind.ByteKeyword ||
                   kind == SyntaxKind.SByteKeyword ||
                   kind == SyntaxKind.ShortKeyword ||
                   kind == SyntaxKind.UShortKeyword ||
                   kind == SyntaxKind.IntKeyword ||
                   kind == SyntaxKind.UIntKeyword ||
                   kind == SyntaxKind.LongKeyword ||
                   kind == SyntaxKind.ULongKeyword ||
                   kind == SyntaxKind.NIntKeyword ||
                   kind == SyntaxKind.NUIntKeyword ||
                   kind == SyntaxKind.StringKeyword ||
                   kind == SyntaxKind.VarKeyword;
        }

        private bool IsTypeStart(SyntaxKind kind) {
            return IsPredefinedType(kind) || kind == SyntaxKind.IdentifierToken;
        }

        private string ParseQualifiedNameText() {
            string text = ConsumeIdentifier("Expected identifier");
            while (Check(SyntaxKind.DotToken)) {
                Advance();
                text = text + "." + ConsumeIdentifier("Expected identifier");
            }
            return text;
        }

        private void SkipModifiers() {
            while (SyntaxFacts.IsModifier(Current().Kind())) {
                Advance();
            }
        }

        private void SkipTypeArgumentOrParameterList() {
            if (!Check(SyntaxKind.LessToken)) {
                return;
            }
            int depth = 0;
            while (!Check(SyntaxKind.EndOfFileToken)) {
                if (Check(SyntaxKind.LessToken)) { depth = depth + 1; }
                if (Check(SyntaxKind.GreaterToken)) { depth = depth - 1; }
                Advance();
                if (depth == 0) { return; }
            }
        }

        private int BinaryPrecedence(SyntaxKind kind) {
            if (kind == SyntaxKind.StarToken || kind == SyntaxKind.SlashToken || kind == SyntaxKind.PercentToken) { return 10; }
            if (kind == SyntaxKind.PlusToken || kind == SyntaxKind.MinusToken) { return 9; }
            if (kind == SyntaxKind.LessToken || kind == SyntaxKind.LessEqualsToken ||
                kind == SyntaxKind.GreaterToken || kind == SyntaxKind.GreaterEqualsToken) { return 8; }
            if (kind == SyntaxKind.EqualsEqualsToken || kind == SyntaxKind.BangEqualsToken) { return 7; }
            if (kind == SyntaxKind.AmpersandToken) { return 6; }
            if (kind == SyntaxKind.CaretToken) { return 5; }
            if (kind == SyntaxKind.PipeToken) { return 4; }
            if (kind == SyntaxKind.AmpersandAmpersandToken) { return 3; }
            if (kind == SyntaxKind.PipePipeToken) { return 2; }
            return 0;
        }

        private SyntaxToken Current() {
            return Peek(0);
        }

        private SyntaxToken Previous() {
            if (index == 0) { return tokens.Get(0); }
            return tokens.Get(index - 1);
        }

        private int SpanLength(SyntaxToken start, SyntaxToken end) {
            int length = end.Position() + end.Text().Length - start.Position();
            if (length < 0) { return 0; }
            return length;
        }

        private SyntaxToken Peek(int offset) {
            int target = index + offset;
            if (target >= tokens.Count()) {
                return tokens.Get(tokens.Count() - 1);
            }
            return tokens.Get(target);
        }

        private bool Check(SyntaxKind kind) {
            return Current().Kind() == kind;
        }

        private SyntaxToken Advance() {
            SyntaxToken token = Current();
            if (!Check(SyntaxKind.EndOfFileToken)) {
                index = index + 1;
                if (buildProgress != null && index % 300 == 0) {
                    buildProgress.Update(index, tokens.Count(), "Parsed " + index + " tokens");
                }
            }
            return token;
        }

        private SyntaxToken Consume(SyntaxKind kind, string message) {
            if (Check(kind)) {
                return Advance();
            }
            diagnostics.Report(Current().Line(), Current().Column(), message);
            return new SyntaxToken(kind, "", Current().Line(), Current().Column(), Current().Position());
        }

        private string ConsumeIdentifier(string message) {
            if (Current().Kind() == SyntaxKind.IdentifierToken) {
                return Advance().Text();
            }
            diagnostics.Report(Current().Line(), Current().Column(), message);
            return "";
        }

        private UsingDirectiveSyntax[] AppendUsing(UsingDirectiveSyntax[] items, int count, UsingDirectiveSyntax item) {
            UsingDirectiveSyntax[] next = new UsingDirectiveSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private NamespaceDeclarationSyntax[] AppendNamespace(NamespaceDeclarationSyntax[] items, int count, NamespaceDeclarationSyntax item) {
            NamespaceDeclarationSyntax[] next = new NamespaceDeclarationSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private ClassDeclarationSyntax[] AppendClass(ClassDeclarationSyntax[] items, int count, ClassDeclarationSyntax item) {
            ClassDeclarationSyntax[] next = new ClassDeclarationSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private MethodDeclarationSyntax[] AppendMethod(MethodDeclarationSyntax[] items, int count, MethodDeclarationSyntax item) {
            MethodDeclarationSyntax[] next = new MethodDeclarationSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

		private FieldDeclarationSyntax[] AppendField(FieldDeclarationSyntax[] items, int count, FieldDeclarationSyntax item) {
			FieldDeclarationSyntax[] next = new FieldDeclarationSyntax[count + 1];
			int i = 0;
			while (i < count) {
				next[i] = items[i];
				i = i + 1;
			}
			next[count] = item;
			return next;
		}

		private EnumDeclarationSyntax[] AppendEnum(EnumDeclarationSyntax[] items, int count, EnumDeclarationSyntax item) {
			EnumDeclarationSyntax[] next = new EnumDeclarationSyntax[count + 1];
			int i = 0;
			while (i < count) {
				next[i] = items[i];
				i = i + 1;
			}
			next[count] = item;
			return next;
		}

		private InterfaceDeclarationSyntax[] AppendInterface(InterfaceDeclarationSyntax[] items, int count, InterfaceDeclarationSyntax item) {
			InterfaceDeclarationSyntax[] next = new InterfaceDeclarationSyntax[count + 1];
			int i = 0;
			while (i < count) {
				next[i] = items[i];
				i = i + 1;
			}
			next[count] = item;
			return next;
		}

        private ParameterSyntax[] AppendParameter(ParameterSyntax[] items, int count, ParameterSyntax item) {
            ParameterSyntax[] next = new ParameterSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private StatementSyntax[] AppendStatement(StatementSyntax[] items, int count, StatementSyntax item) {
            StatementSyntax[] next = new StatementSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private ExpressionSyntax[] AppendExpression(ExpressionSyntax[] items, int count, ExpressionSyntax item) {
            ExpressionSyntax[] next = new ExpressionSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private string[] AppendString(string[] items, int count, string item) {
            string[] next = new string[count + 1]; int i = 0;
            while (i < count) { next[i] = items[i]; i = i + 1; }
            next[count] = item; return next;
        }

		private EnumMemberSyntax[] AppendEnumMember(EnumMemberSyntax[] items, int count, EnumMemberSyntax item) {
			EnumMemberSyntax[] next = new EnumMemberSyntax[count + 1];
			int i = 0;
			while (i < count) {
				next[i] = items[i];
				i = i + 1;
			}
			next[count] = item;
			return next;
		}

		private int ParseDecimalIntLiteral(SyntaxToken token) {
			string text = token.Text();

			int value = 0;
			int i = 0;

			while (i < text.Length) {
				string ch = text[i];

				int digit = -1;

				if (ch == "0") { digit = 0; }
				if (ch == "1") { digit = 1; }
				if (ch == "2") { digit = 2; }
				if (ch == "3") { digit = 3; }
				if (ch == "4") { digit = 4; }
				if (ch == "5") { digit = 5; }
				if (ch == "6") { digit = 6; }
				if (ch == "7") { digit = 7; }
				if (ch == "8") { digit = 8; }
				if (ch == "9") { digit = 9; }

				if (digit < 0) {
					diagnostics.Report(token.Line(), token.Column(), "Invalid integer literal '" + text + "'");
					return 0;
				}

				value = value * 10 + digit;
				i = i + 1;
			}

			return value;
		}
    }
}
