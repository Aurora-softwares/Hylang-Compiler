using Hydrogen.Compiler.Syntax;

namespace Hydrogen.Compiler.CodeGen.X64 {
    // The direct backend intentionally starts with an executable language subset.
    // It does not rely on C emission, an assembler, or a linker at runtime.
    public class DirectImageResult {
        private bool success;
        private byte[] image;
        private string message;

        public DirectImageResult(bool inputSuccess, byte[] inputImage, string inputMessage) {
            success = inputSuccess;
            image = inputImage;
            message = inputMessage;
        }

        public bool Success() { return success; }
        public byte[] Image() { return image; }
        public string Message() { return message; }
    }

    public class DirectMainCompiler {
        private X64Assembler code;
        private string[] localNames;
        private int localCount;
        private string[] payloads;
        private int payloadCount;
        private int[] payloadPatchOffsets;
        private int[] payloadPatchIndexes;
        private int payloadPatchCount;
        private string failure;

        public DirectImageResult Compile(CompilationUnitSyntax root) {
            code = new X64Assembler();
            localNames = new string[0];
            localCount = 0;
            payloads = new string[0];
            payloadCount = 0;
            payloadPatchOffsets = new int[0];
            payloadPatchIndexes = new int[0];
            payloadPatchCount = 0;
            failure = "";

            MethodDeclarationSyntax main = FindMain(root);
            if (main == null) {
                return Failed("no static Main method");
            }

            // Keep local slots stable while expressions temporarily use rsp.
            // rbp remains the immutable base for every local in this entrypoint.
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xe5); // mov rbp, rsp
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xec); code.Emit32(4096); // sub rsp, 4096

            if (!CompileStatement(main.Body())) {
                return Failed(failure);
            }
            EmitExitImmediate(0);

            ElfImageBuilder imageBuilder = new ElfImageBuilder();
            return new DirectImageResult(true, imageBuilder.BuildCodeAndData(code.ToArray(), payloads, payloadPatchOffsets, payloadPatchIndexes), "");
        }

        private DirectImageResult Failed(string message) {
            return new DirectImageResult(false, new byte[0], message);
        }

        private MethodDeclarationSyntax FindMain(CompilationUnitSyntax root) {
            MethodDeclarationSyntax result = FindMainInClasses(root.Classes());
            if (result != null) { return result; }
            NamespaceDeclarationSyntax[] namespaces = root.Namespaces();
            int i = 0;
            while (i < namespaces.Length) {
                result = FindMainInClasses(namespaces[i].Classes());
                if (result != null) { return result; }
                i = i + 1;
            }
            return null;
        }

        private MethodDeclarationSyntax FindMainInClasses(ClassDeclarationSyntax[] classes) {
            int c = 0;
            while (c < classes.Length) {
                MethodDeclarationSyntax[] methods = classes[c].Methods();
                int m = 0;
                while (m < methods.Length) {
                    if (methods[m].IsStatic() && methods[m].Name() == "Main") {
                        return methods[m];
                    }
                    m = m + 1;
                }
                c = c + 1;
            }
            return null;
        }

        private bool CompileStatement(StatementSyntax statement) {
            if (statement == null) { return true; }
            int kind = statement.Kind();
            if (kind == StatementSyntax.KindBlock()) {
                StatementSyntax[] items = statement.Statements();
                int i = 0;
                while (i < items.Length) {
                    if (!CompileStatement(items[i])) { return false; }
                    i = i + 1;
                }
                return true;
            }
            if (kind == StatementSyntax.KindVariableDeclaration()) {
                int slot = AddLocal(statement.Name());
                if (statement.Initializer() == null) {
                    EmitMoveRaxImmediate(0);
                } else if (!CompileExpression(statement.Initializer())) {
                    return false;
                }
                EmitStoreLocal(slot);
                return true;
            }
            if (kind == StatementSyntax.KindExpressionStatement()) {
                return CompileExpression(statement.Expression());
            }
            if (kind == StatementSyntax.KindReturnStatement()) {
                if (statement.Expression() == null) {
                    EmitExitImmediate(0);
                } else {
                    if (!CompileExpression(statement.Expression())) { return false; }
                    EmitExitFromRax();
                }
                return true;
            }
            if (kind == StatementSyntax.KindIfStatement()) {
                if (!CompileExpression(statement.Condition())) { return false; }
                int elsePatch = EmitJumpIfZero();
                if (!CompileStatement(statement.ThenStatement())) { return false; }
                int endPatch = EmitJump();
                PatchRelative(elsePatch, code.Position());
                if (!CompileStatement(statement.ElseStatement())) { return false; }
                PatchRelative(endPatch, code.Position());
                return true;
            }
            if (kind == StatementSyntax.KindWhileStatement()) {
                int conditionPosition = code.Position();
                if (!CompileExpression(statement.Condition())) { return false; }
                int exitPatch = EmitJumpIfZero();
                if (!CompileStatement(statement.Body())) { return false; }
                int backPatch = EmitJump();
                PatchRelative(backPatch, conditionPosition);
                PatchRelative(exitPatch, code.Position());
                return true;
            }
            failure = "unsupported statement in direct native backend";
            return false;
        }

        private bool CompileExpression(ExpressionSyntax expression) {
            if (expression == null) {
                EmitMoveRaxImmediate(0);
                return true;
            }
            int kind = expression.Kind();
            if (kind == ExpressionSyntax.KindLiteral()) {
                if (expression.LiteralKind() == "number") {
                    EmitMoveRaxImmediate(ParseInt(expression.LiteralText()));
                    return true;
                }
                if (expression.LiteralKind() == "bool") {
                    if (expression.LiteralText() == "true") { EmitMoveRaxImmediate(1); }
                    else { EmitMoveRaxImmediate(0); }
                    return true;
                }
                failure = "string literals are only supported as System.Console.WriteLine arguments";
                return false;
            }
            if (kind == ExpressionSyntax.KindName()) {
                int slot = FindLocal(expression.Name());
                if (slot < 0) {
                    failure = "unknown direct-backend local '" + expression.Name() + "'";
                    return false;
                }
                EmitLoadLocal(slot);
                return true;
            }
            if (kind == ExpressionSyntax.KindAssignment()) {
                if (expression.Target().Kind() != ExpressionSyntax.KindName()) {
                    failure = "direct backend only supports assignment to locals";
                    return false;
                }
                int assignmentSlot = FindLocal(expression.Target().Name());
                if (assignmentSlot < 0) {
                    failure = "assignment target is not a local";
                    return false;
                }
                if (!CompileExpression(expression.Value())) { return false; }
                EmitStoreLocal(assignmentSlot);
                return true;
            }
            if (kind == ExpressionSyntax.KindUnary()) {
                if (!CompileExpression(expression.UnaryOperand())) { return false; }
                if (expression.UnaryOperatorKind() == SyntaxKind.MinusToken) {
                    code.EmitByte(0x48); code.EmitByte(0xf7); code.EmitByte(0xd8); // neg rax
                    return true;
                }
                if (expression.UnaryOperatorKind() == SyntaxKind.BangToken) {
                    code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xc0); // test rax, rax
                    code.EmitByte(0x0f); code.EmitByte(0x94); code.EmitByte(0xc0); // sete al
                    code.EmitByte(0x48); code.EmitByte(0x0f); code.EmitByte(0xb6); code.EmitByte(0xc0); // movzx rax, al
                    return true;
                }
                failure = "unsupported unary operator";
                return false;
            }
            if (kind == ExpressionSyntax.KindBinary()) {
                return CompileBinary(expression);
            }
            if (kind == ExpressionSyntax.KindInvocation()) {
                return CompileInvocation(expression);
            }
            failure = "unsupported expression in direct native backend";
            return false;
        }

        private bool CompileBinary(ExpressionSyntax expression) {
            if (!CompileExpression(expression.Left())) { return false; }
            code.EmitByte(0x50); // push rax
            if (!CompileExpression(expression.Right())) { return false; }
            code.EmitByte(0x59); // pop rcx (left), rax is right
            SyntaxKind op = expression.OperatorKind();
            if (op == SyntaxKind.PlusToken) {
                code.EmitByte(0x48); code.EmitByte(0x01); code.EmitByte(0xc8); // add rax, rcx
                return true;
            }
            if (op == SyntaxKind.MinusToken) {
                code.EmitByte(0x48); code.EmitByte(0x29); code.EmitByte(0xc1); // sub rcx, rax
                code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc8); // mov rax, rcx
                return true;
            }
            if (op == SyntaxKind.StarToken) {
                code.EmitByte(0x48); code.EmitByte(0x0f); code.EmitByte(0xaf); code.EmitByte(0xc8); // imul rcx, rax
                code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc8); // mov rax, rcx
                return true;
            }
            if (op == SyntaxKind.SlashToken || op == SyntaxKind.PercentToken) {
                code.EmitByte(0x48); code.EmitByte(0x91); // xchg rax, rcx
                code.EmitByte(0x48); code.EmitByte(0x31); code.EmitByte(0xd2); // xor rdx, rdx
                code.EmitByte(0x48); code.EmitByte(0xf7); code.EmitByte(0xf1); // div rcx
                if (op == SyntaxKind.PercentToken) {
                    code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xd0); // mov rax, rdx
                }
                return true;
            }
            if (op == SyntaxKind.EqualsEqualsToken || op == SyntaxKind.BangEqualsToken ||
                op == SyntaxKind.LessToken || op == SyntaxKind.LessEqualsToken ||
                op == SyntaxKind.GreaterToken || op == SyntaxKind.GreaterEqualsToken) {
                code.EmitByte(0x48); code.EmitByte(0x39); code.EmitByte(0xc1); // cmp rcx, rax
                code.EmitByte(0x0f);
                if (op == SyntaxKind.EqualsEqualsToken) { code.EmitByte(0x94); }
                if (op == SyntaxKind.BangEqualsToken) { code.EmitByte(0x95); }
                if (op == SyntaxKind.LessToken) { code.EmitByte(0x9c); }
                if (op == SyntaxKind.LessEqualsToken) { code.EmitByte(0x9e); }
                if (op == SyntaxKind.GreaterToken) { code.EmitByte(0x9f); }
                if (op == SyntaxKind.GreaterEqualsToken) { code.EmitByte(0x9d); }
                code.EmitByte(0xc0); // setcc al
                code.EmitByte(0x48); code.EmitByte(0x0f); code.EmitByte(0xb6); code.EmitByte(0xc0); // movzx rax, al
                return true;
            }
            failure = "unsupported binary operator";
            return false;
        }

        private bool CompileInvocation(ExpressionSyntax expression) {
            if (!IsConsoleWriteLine(expression.Target())) {
                failure = "direct backend only supports System.Console.WriteLine calls";
                return false;
            }
            ExpressionSyntax[] arguments = expression.Arguments();
            if (arguments.Length != 1 || arguments[0].Kind() != ExpressionSyntax.KindLiteral() || arguments[0].LiteralKind() != "string") {
                failure = "direct System.Console.WriteLine requires one string literal";
                return false;
            }
            int payloadIndex = AddPayload(arguments[0].LiteralText() + "\n");
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc0); code.Emit32(1); // mov rax, 1
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc7); code.Emit32(1); // mov rdi, 1
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x35); // lea rsi, [rip+disp32]
            int patchOffset = code.Position();
            code.Emit32(0);
            AddPayloadPatch(patchOffset, payloadIndex);
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc2); code.Emit32(payloads[payloadIndex].Length); // mov rdx, len
            code.EmitByte(0x0f); code.EmitByte(0x05); // syscall
            EmitMoveRaxImmediate(0);
            return true;
        }

        private bool IsConsoleWriteLine(ExpressionSyntax target) {
            if (target == null || target.Kind() != ExpressionSyntax.KindMemberAccess() || target.MemberName() != "WriteLine") { return false; }
            ExpressionSyntax console = target.Receiver();
            if (console == null || console.Kind() != ExpressionSyntax.KindMemberAccess() || console.MemberName() != "Console") { return false; }
            ExpressionSyntax system = console.Receiver();
            return system != null && system.Kind() == ExpressionSyntax.KindName() && system.Name() == "System";
        }

        private void EmitMoveRaxImmediate(int value) {
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc0); code.Emit32(value);
        }

        private void EmitStoreLocal(int slot) {
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x85); code.Emit32(-8 * (slot + 1)); // mov [rbp-offsetof], rax
        }

        private void EmitLoadLocal(int slot) {
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x85); code.Emit32(-8 * (slot + 1)); // mov rax, [rbp-offsetof]
        }

        private int EmitJumpIfZero() {
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xc0); // test rax, rax
            code.EmitByte(0x0f); code.EmitByte(0x84); // je rel32
            int patch = code.Position();
            code.Emit32(0);
            return patch;
        }

        private int EmitJump() {
            code.EmitByte(0xe9); // jmp rel32
            int patch = code.Position();
            code.Emit32(0);
            return patch;
        }

        private void PatchRelative(int patchOffset, int target) {
            code.Patch32(patchOffset, target - (patchOffset + 4));
        }

        private void EmitExitFromRax() {
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc7); // mov rdi, rax
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc0); code.Emit32(60); // mov rax, 60
            code.EmitByte(0x0f); code.EmitByte(0x05); // syscall
        }

        private void EmitExitImmediate(int exitCode) {
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc0); code.Emit32(60); // mov rax, 60
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc7); code.Emit32(exitCode); // mov rdi, code
            code.EmitByte(0x0f); code.EmitByte(0x05); // syscall
        }

        private int AddLocal(string name) {
            int existing = FindLocal(name);
            if (existing >= 0) { return existing; }
            localNames = AppendString(localNames, localCount, name);
            int result = localCount;
            localCount = localCount + 1;
            return result;
        }

        private int FindLocal(string name) {
            int i = 0;
            while (i < localCount) {
                if (localNames[i] == name) { return i; }
                i = i + 1;
            }
            return -1;
        }

        private int AddPayload(string text) {
            payloads = AppendString(payloads, payloadCount, text);
            int result = payloadCount;
            payloadCount = payloadCount + 1;
            return result;
        }

        private void AddPayloadPatch(int patchOffset, int payloadIndex) {
            payloadPatchOffsets = AppendInt(payloadPatchOffsets, payloadPatchCount, patchOffset);
            payloadPatchIndexes = AppendInt(payloadPatchIndexes, payloadPatchCount, payloadIndex);
            payloadPatchCount = payloadPatchCount + 1;
        }

        private int ParseInt(string text) {
            int start = 0;
            int radix = 10;
            // The bootstrap interpreter intentionally does not promise
            // short-circuit evaluation yet, so guard every string index in
            // nested conditionals rather than relying on `&&` here.
            if (text.Length >= 2) {
                if (text[0] == "0") {
                    if (text[1] == "x" || text[1] == "X") {
                        start = 2;
                        radix = 16;
                    }
                }
            }
            int value = 0;
            int i = start;
            while (i < text.Length) {
                value = value * radix + DigitValue(text[i]);
                i = i + 1;
            }
            return value;
        }

        private int DigitValue(string ch) {
            if (ch == "0") { return 0; }
            if (ch == "1") { return 1; }
            if (ch == "2") { return 2; }
            if (ch == "3") { return 3; }
            if (ch == "4") { return 4; }
            if (ch == "5") { return 5; }
            if (ch == "6") { return 6; }
            if (ch == "7") { return 7; }
            if (ch == "8") { return 8; }
            if (ch == "9") { return 9; }
            if (ch == "a" || ch == "A") { return 10; }
            if (ch == "b" || ch == "B") { return 11; }
            if (ch == "c" || ch == "C") { return 12; }
            if (ch == "d" || ch == "D") { return 13; }
            if (ch == "e" || ch == "E") { return 14; }
            return 15;
        }

        private string[] AppendString(string[] items, int count, string item) {
            string[] next = new string[count + 1];
            int i = 0;
            while (i < count) { next[i] = items[i]; i = i + 1; }
            next[count] = item;
            return next;
        }

        private int[] AppendInt(int[] items, int count, int item) {
            int[] next = new int[count + 1];
            int i = 0;
            while (i < count) { next[i] = items[i]; i = i + 1; }
            next[count] = item;
            return next;
        }
    }
}
