using Hydrogen.Compiler.Binding;
using Hydrogen.Compiler.IR;

namespace Hydrogen.Compiler.CodeGen.X64 {
    public class AustralisBytecodeBuilder {
        private byte[] bytes; private int length; private bool valid;
        public AustralisBytecodeBuilder() { bytes = new byte[65536]; length = 0; valid = true; }
        public bool IsValid() { return valid; }
        public int Position() { return length; }
        public void Byte(int value) {
            if (!valid || value < 0 || value > 255 || length >= bytes.Length) { valid = false; return; }
            bytes[length] = (byte)value; length = length + 1;
        }
        public void U32(long value) {
            int i = 0; while (i < 4) { Byte((int)(value % 256)); value = value / 256; i = i + 1; }
        }
        public void Patch32(int offset, long value) {
            if (!valid || offset < 0 || offset + 4 > length) { valid = false; return; }
            int i = 0;
            while (i < 4) { bytes[offset + i] = (byte)(value % 256); value = value / 256; i = i + 1; }
        }
        public byte[] Bytes() {
            if (!valid) { return null; }
            byte[] result = new byte[length]; int i = 0;
            while (i < length) { result[i] = bytes[i]; i = i + 1; }
            return result;
        }
    }

    // AUEX v1 keeps the original syscall opcodes and adds a checked scalar VM.
    public class AustralisExecImageBuilder {
        private AustralisBytecodeBuilder code;
        private byte[] data; private int dataLength; private int scratchCapacity;
        private int[] scratchPatches; private int scratchPatchCount;
        private int[] heapPatches; private int heapPatchCount; private bool needsHeap;
        private string[] localNames; private string[] localTypes; private int localCount;
        private int[] breakPatches; private int breakCount;
        private int[] continuePatches; private int continueCount;
        private int loopDepth; private string valueType; private ElfImageBuilder ascii;
        private string entryArgumentName;
        private IrFunction[] functions; private int[] functionStarts;
        private int[] callPatches; private int[] callTargets; private int callCount;
        private bool compilingMain;

        private static long DataBase() { return 5242880; }

        public byte[] Build(BoundProgram program) {
            if (program == null || program.Module() == null) { return null; }
            IrFunction main = FindMain(program.Module());
            if (main == null || main.Body() == null) { return null; }
            entryArgumentName = "args";
            functions = program.Module().Functions();
            functionStarts = new int[functions.Length];
            int functionIndex = 0;
            while (functionIndex < functionStarts.Length) {
                functionStarts[functionIndex] = -1; functionIndex = functionIndex + 1;
            }
            callPatches = new int[0]; callTargets = new int[0]; callCount = 0;
            compilingMain = true;
            if (main.Declaration() != null && main.Declaration().Parameters().Length == 1) {
                entryArgumentName = main.Declaration().Parameters()[0].Name();
            }
            code = new AustralisBytecodeBuilder(); data = new byte[65536]; dataLength = 0;
            scratchCapacity = 0; scratchPatches = new int[0]; scratchPatchCount = 0;
            heapPatches = new int[0]; heapPatchCount = 0; needsHeap = false;
            localNames = new string[0]; localTypes = new string[0]; localCount = 0;
            breakPatches = new int[0]; breakCount = 0;
            continuePatches = new int[0]; continueCount = 0;
            loopDepth = 0; valueType = "void"; ascii = new ElfImageBuilder();
            if (!CompileStatement(main.Body())) { return null; }
            code.Byte(1); code.Byte(0);
            int pending = 0;
            while (pending < callCount) {
                int target = callTargets[pending];
                if (functionStarts[target] < 0 && !CompileFunction(target)) { return null; }
                pending = pending + 1;
            }
            pending = 0;
            while (pending < callCount) {
                code.Patch32(callPatches[pending], functionStarts[callTargets[pending]]);
                pending = pending + 1;
            }
            if (!code.IsValid() || dataLength + scratchCapacity > 65536 ||
                (needsHeap && dataLength + scratchCapacity >= 65536)) { return null; }
            long scratchAddress = DataBase() + dataLength; int sp = 0;
            while (sp < scratchPatchCount) { code.Patch32(scratchPatches[sp], scratchAddress); sp = sp + 1; }
            long heapAddress = scratchAddress + scratchCapacity; sp = 0;
            while (sp < heapPatchCount) { code.Patch32(heapPatches[sp], heapAddress); sp = sp + 1; }
            byte[] codeBytes = code.Bytes();
            if (codeBytes == null || codeBytes.Length < 1) { return null; }
            int dataCapacity = dataLength + scratchCapacity;
            if (needsHeap) { dataCapacity = 65536; }
            int dataOffset = 32 + codeBytes.Length;
            byte[] output = new byte[dataOffset + dataLength];
            output[0] = (byte)65; output[1] = (byte)85; output[2] = (byte)69; output[3] = (byte)88;
            output[4] = (byte)1; output[5] = (byte)32;
            Write32(output, 8, codeBytes.Length); Write32(output, 12, dataLength);
            Write32(output, 16, dataCapacity); Write32(output, 20, 0);
            int i = 0;
            while (i < codeBytes.Length) { output[32 + i] = codeBytes[i]; i = i + 1; }
            i = 0; while (i < dataLength) { output[dataOffset + i] = data[i]; i = i + 1; }
            Write32(output, 24, Crc32(output, 32, codeBytes.Length));
            Write32(output, 28, Crc32(output, dataOffset, dataLength));
            return output;
        }

        private IrFunction FindMain(IrModule module) {
            IrFunction selected = null; IrFunction[] functions = module.Functions(); int i = 0;
            while (i < functions.Length) {
                IrFunction candidate = functions[i];
                if (IsMainName(candidate.Name())) {
                    if (candidate.ParameterTypes().Length == 1) {
                        if (candidate.ParameterTypes()[0] == "string[]") {
                            if (candidate.ReturnType() == "void" || candidate.ReturnType() == "int") {
                                if (selected != null) { return null; }
                                selected = candidate;
                            }
                        }
                    }
                }
                i = i + 1;
            }
            return selected;
        }
        private bool IsMainName(string name) {
            if (name.Length < 5) { return false; }
            int start = name.Length - 5;
            return name[start] == "." && name[start + 1] == "M" && name[start + 2] == "a" &&
                name[start + 3] == "i" && name[start + 4] == "n";
        }

        private bool CompileFunction(int index) {
            IrFunction function = functions[index];
            if (function == null || function.Body() == null ||
                function.Declaration() == null || !function.Declaration().IsStatic()) {
                return false;
            }
            IrParameter[] parameters = function.Declaration().Parameters();
            if (parameters.Length > 255) { return false; }
            functionStarts[index] = code.Position();
            localNames = new string[0]; localTypes = new string[0]; localCount = 0;
            breakPatches = new int[0]; breakCount = 0;
            continuePatches = new int[0]; continueCount = 0; loopDepth = 0;
            compilingMain = false;
            int parameter = 0;
            while (parameter < parameters.Length) {
                string type = parameters[parameter].Type().DisplayName();
                if (!Scalar(type)) { return false; }
                AddLocal(parameters[parameter].Name(), type);
                parameter = parameter + 1;
            }
            if (!CompileStatement(function.Body())) { return false; }
            if (function.ReturnType() == "void") { code.Byte(62); }
            else { EmitPush(0); code.Byte(61); }
            return code.IsValid();
        }

        private bool CompileStatement(IrStatement statement) {
            if (statement == null) { return true; }
            int kind = statement.Kind();
            if (kind == IrStatement.KindBlock()) {
                int saved = localCount; IrStatement[] statements = statement.Statements(); int i = 0;
                while (i < statements.Length) {
                    if (!CompileStatement(statements[i])) { return false; }
                    i = i + 1;
                }
                localCount = saved; return true;
            }
            if (kind == IrStatement.KindVariableDeclaration()) {
                string type = statement.Type().DisplayName();
                if (!Scalar(type) || localCount >= 256) { return false; }
                if (statement.Initializer() == null) { EmitPush(0); valueType = type; }
                else if (!CompileExpression(statement.Initializer()) || !Compatible(valueType, type)) { return false; }
                int slot = AddLocal(statement.Name(), type);
                code.Byte(13); code.Byte(slot); code.Byte(14); return code.IsValid();
            }
            if (kind == IrStatement.KindExpressionStatement()) {
                if (!CompileExpression(statement.Expression())) { return false; }
                if (valueType != "void") { code.Byte(14); }
                return code.IsValid();
            }
            if (kind == IrStatement.KindReturnStatement()) {
                if (statement.Expression() == null) {
                    if (compilingMain) { code.Byte(1); code.Byte(0); }
                    else { code.Byte(62); }
                    return code.IsValid();
                }
                if (!CompileExpression(statement.Expression()) ||
                    (compilingMain && !Numeric(valueType)) ||
                    (!compilingMain && !Scalar(valueType))) { return false; }
                if (compilingMain) { code.Byte(29); }
                else { code.Byte(61); }
                return code.IsValid();
            }
            if (kind == IrStatement.KindIfStatement()) {
                if (!CompileExpression(statement.Condition()) || valueType != "bool") { return false; }
                int falsePatch = EmitConditionalJump();
                if (!CompileStatement(statement.ThenStatement())) { return false; }
                if (statement.ElseStatement() != null) {
                    int endPatch = EmitJump(); code.Patch32(falsePatch, code.Position());
                    if (!CompileStatement(statement.ElseStatement())) { return false; }
                    code.Patch32(endPatch, code.Position());
                } else { code.Patch32(falsePatch, code.Position()); }
                return code.IsValid();
            }
            if (kind == IrStatement.KindWhileStatement()) {
                int savedBreaks = breakCount; int savedContinues = continueCount;
                int condition = code.Position(); loopDepth = loopDepth + 1;
                if (!CompileExpression(statement.Condition()) || valueType != "bool") { return false; }
                int exitPatch = EmitConditionalJump();
                if (!CompileStatement(statement.Body())) { return false; }
                PatchRange(continuePatches, savedContinues, continueCount, condition);
                continueCount = savedContinues; EmitAbsoluteJump(condition);
                int end = code.Position(); code.Patch32(exitPatch, end);
                PatchRange(breakPatches, savedBreaks, breakCount, end);
                breakCount = savedBreaks; loopDepth = loopDepth - 1; return code.IsValid();
            }
            if (kind == IrStatement.KindForStatement()) {
                int savedLocals = localCount;
                if (!CompileStatement(statement.ForInitializer())) { return false; }
                int savedBreaks = breakCount; int savedContinues = continueCount;
                int condition = code.Position(); loopDepth = loopDepth + 1;
                if (statement.Condition() == null) { EmitPush(1); valueType = "bool"; }
                else if (!CompileExpression(statement.Condition()) || valueType != "bool") { return false; }
                int exitPatch = EmitConditionalJump();
                if (!CompileStatement(statement.Body())) { return false; }
                int increment = code.Position();
                PatchRange(continuePatches, savedContinues, continueCount, increment);
                continueCount = savedContinues;
                if (statement.ForIncrement() != null) {
                    if (!CompileExpression(statement.ForIncrement())) { return false; }
                    if (valueType != "void") { code.Byte(14); }
                }
                EmitAbsoluteJump(condition);
                int end = code.Position(); code.Patch32(exitPatch, end);
                PatchRange(breakPatches, savedBreaks, breakCount, end);
                breakCount = savedBreaks; loopDepth = loopDepth - 1;
                localCount = savedLocals; return code.IsValid();
            }
            if (kind == IrStatement.KindBreakStatement() || kind == IrStatement.KindContinueStatement()) {
                if (loopDepth < 1) { return false; }
                int patch = EmitJump();
                if (kind == IrStatement.KindBreakStatement()) {
                    breakPatches = AppendInt(breakPatches, breakCount, patch); breakCount = breakCount + 1;
                } else {
                    continuePatches = AppendInt(continuePatches, continueCount, patch); continueCount = continueCount + 1;
                }
                return code.IsValid();
            }
            return false;
        }

        private bool CompileExpression(IrExpression expression) {
            if (expression == null) { EmitPush(0); valueType = "int"; return true; }
            int kind = expression.Kind();
            if (kind == IrExpression.KindLiteral()) {
                if (expression.LiteralKind() == "number") {
                    EmitPush(ParseInt(expression.LiteralText())); valueType = "int"; return code.IsValid();
                }
                if (expression.LiteralKind() == "bool") {
                    if (expression.LiteralText() == "true") { EmitPush(1); } else { EmitPush(0); }
                    valueType = "bool"; return code.IsValid();
                }
                if (expression.LiteralKind() == "string") {
                    if (expression.LiteralText().Length > 255) { return false; }
                    int offset = AddAscii(expression.LiteralText(), false);
                    if (offset < 0 || dataLength >= data.Length) { return false; }
                    data[dataLength] = (byte)0; dataLength = dataLength + 1;
                    EmitPush((int)(DataBase() + offset));
                    valueType = "string"; return code.IsValid();
                }
                return false;
            }
            if (kind == IrExpression.KindMemberAccess()) {
                IrExpression receiver = expression.Receiver();
                if (expression.MemberName() != "Length" || receiver == null) { return false; }
                if (receiver.Kind() == IrExpression.KindName() &&
                    receiver.Name() == entryArgumentName) {
                    code.Byte(45); valueType = "int"; return code.IsValid();
                }
                if (!CompileExpression(receiver)) { return false; }
                if (valueType == "string") { code.Byte(49); }
                else if (valueType == "byte[]") { code.Byte(65); }
                else { return false; }
                valueType = "int"; return code.IsValid();
            }
            if (kind == IrExpression.KindIndex()) {
                IrExpression receiver2 = expression.Receiver();
                if (receiver2 != null && receiver2.Kind() == IrExpression.KindName() &&
                    receiver2.Name() == entryArgumentName) {
                    if (!CompileExpression(expression.Index()) || !Numeric(valueType)) {
                        return false;
                    }
                    code.Byte(46); valueType = "string"; return code.IsValid();
                }
                if (!CompileExpression(receiver2) || valueType != "byte[]" ||
                    !CompileExpression(expression.Index()) || !Numeric(valueType)) {
                    return false;
                }
                code.Byte(66); valueType = "byte"; return code.IsValid();
            }
            if (kind == IrExpression.KindArrayCreation()) {
                if (expression.Type() == null || expression.Type().DisplayName() != "byte" ||
                    !CompileExpression(expression.Size()) || !Numeric(valueType)) {
                    return false;
                }
                code.Byte(64); EmitHeapAddress();
                valueType = "byte[]"; return code.IsValid();
            }
            if (kind == IrExpression.KindName()) {
                int slot = FindLocal(expression.Name());
                if (slot < 0) { return false; }
                code.Byte(12); code.Byte(slot); valueType = localTypes[slot]; return code.IsValid();
            }
            if (kind == IrExpression.KindAssignment()) {
                IrExpression target = expression.Target();
                if (target != null && target.Kind() == IrExpression.KindIndex()) {
                    if (!CompileExpression(target.Receiver()) || valueType != "byte[]" ||
                        !CompileExpression(target.Index()) || !Numeric(valueType) ||
                        !CompileExpression(expression.Value()) || !Numeric(valueType)) {
                        return false;
                    }
                    code.Byte(67); valueType = "byte"; return code.IsValid();
                }
                if (target == null || target.Kind() != IrExpression.KindName()) { return false; }
                int slot2 = FindLocal(target.Name());
                if (slot2 < 0 || !CompileExpression(expression.Value()) ||
                    !Compatible(valueType, localTypes[slot2])) { return false; }
                code.Byte(13); code.Byte(slot2); valueType = localTypes[slot2]; return code.IsValid();
            }
            if (kind == IrExpression.KindCast()) {
                string castType = expression.CastType().DisplayName();
                if (!Scalar(castType) || !CompileExpression(expression.CastExpression()) ||
                    !Numeric(valueType) || !Numeric(castType)) { return false; }
                valueType = castType; return true;
            }
            if (kind == IrExpression.KindUnary()) {
                if (!CompileExpression(expression.UnaryOperand())) { return false; }
                int unary = expression.UnaryOperatorKind();
                if (unary == IrOperator.PlusToken() && Numeric(valueType)) { return true; }
                if (unary == IrOperator.MinusToken() && Numeric(valueType)) { code.Byte(20); return code.IsValid(); }
                if (unary == IrOperator.BangToken() && valueType == "bool") {
                    code.Byte(27); valueType = "bool"; return code.IsValid();
                }
                return false;
            }
            if (kind == IrExpression.KindBinary()) { return CompileBinary(expression); }
            if (kind == IrExpression.KindInvocation()) { return CompileInvocation(expression); }
            return false;
        }

        private bool CompileBinary(IrExpression expression) {
            int op = expression.OperatorKind();
            if (op == IrOperator.AmpersandAmpersandToken() || op == IrOperator.PipePipeToken()) {
                if (!CompileExpression(expression.Left()) || valueType != "bool") { return false; }
                int shortPatch = EmitConditionalJump();
                if (op == IrOperator.PipePipeToken()) {
                    EmitPush(1); int endPatch = EmitJump(); code.Patch32(shortPatch, code.Position());
                    if (!CompileExpression(expression.Right()) || valueType != "bool") { return false; }
                    code.Patch32(endPatch, code.Position());
                } else {
                    if (!CompileExpression(expression.Right()) || valueType != "bool") { return false; }
                    int endPatch2 = EmitJump(); code.Patch32(shortPatch, code.Position()); EmitPush(0);
                    code.Patch32(endPatch2, code.Position());
                }
                valueType = "bool"; return code.IsValid();
            }
            if (!CompileExpression(expression.Left())) { return false; }
            string leftType = valueType;
            if (!CompileExpression(expression.Right())) { return false; }
            string rightType = valueType;
            bool equality = op == IrOperator.EqualsEqualsToken() || op == IrOperator.BangEqualsToken();
            if (equality) {
                if (!Compatible(leftType, rightType)) { return false; }
                if (leftType == "string" && rightType == "string") {
                    code.Byte(47);
                    if (op == IrOperator.BangEqualsToken()) { code.Byte(27); }
                    valueType = "bool"; return code.IsValid();
                }
                if (op == IrOperator.EqualsEqualsToken()) { code.Byte(21); } else { code.Byte(22); }
                valueType = "bool"; return code.IsValid();
            }
            if (!Numeric(leftType) || !Numeric(rightType)) { return false; }
            if (op == IrOperator.PlusToken()) { code.Byte(15); valueType = expression.ResultType(); }
            else if (op == IrOperator.MinusToken()) { code.Byte(16); valueType = expression.ResultType(); }
            else if (op == IrOperator.StarToken()) { code.Byte(17); valueType = expression.ResultType(); }
            else if (op == IrOperator.SlashToken()) { code.Byte(18); valueType = expression.ResultType(); }
            else if (op == IrOperator.PercentToken()) { code.Byte(19); valueType = expression.ResultType(); }
            else if (op == IrOperator.LessToken()) { code.Byte(23); valueType = "bool"; }
            else if (op == IrOperator.LessEqualsToken()) { code.Byte(24); valueType = "bool"; }
            else if (op == IrOperator.GreaterToken()) { code.Byte(25); valueType = "bool"; }
            else if (op == IrOperator.GreaterEqualsToken()) { code.Byte(26); valueType = "bool"; }
            else { return false; }
            if (valueType == "") { valueType = leftType; }
            return code.IsValid();
        }

        private bool CompileInvocation(IrExpression expression) {
            string name = QualifiedName(expression.Target()); IrExpression[] args = expression.Arguments();
            if (name == "System.Console.ReadLine") {
                if (args.Length != 0) { return false; }
                code.Byte(57); EmitHeapAddress();
                valueType = "string"; return code.IsValid();
            }
            if (name == "System.Australis.Terminal.EndOfInput") {
                if (args.Length != 0) { return false; }
                code.Byte(87); valueType = "bool"; return code.IsValid();
            }
            if (name == "System.Australis.Terminal.ReadKey") {
                if (args.Length != 0) { return false; }
                code.Byte(88); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Terminal.MoveCursor") {
                if (args.Length != 2 || !CompileExpression(args[0]) ||
                    !Numeric(valueType) || !CompileExpression(args[1]) ||
                    !Numeric(valueType)) { return false; }
                code.Byte(89); valueType = "void"; return code.IsValid();
            }
            if (name == "System.IO.File.ReadAllText") {
                if (args.Length != 1 || !CompileExpression(args[0]) || valueType != "string") {
                    return false;
                }
                code.Byte(56); EmitHeapAddress();
                valueType = "string"; return code.IsValid();
            }
            if (name == "System.IO.File.Exists") {
                if (args.Length != 1 || !CompileExpression(args[0]) || valueType != "string") {
                    return false;
                }
                code.Byte(51); code.Byte(0); EmitPush(1); code.Byte(21);
                valueType = "bool"; return code.IsValid();
            }
            if (name == "System.IO.File.WriteAllText") {
                if (args.Length != 2 || !CompileExpression(args[0]) || valueType != "string" ||
                    !CompileExpression(args[1]) || valueType != "string") {
                    return false;
                }
                code.Byte(58); valueType = "void"; return code.IsValid();
            }
            if (name == "System.Convert.ToInt32") {
                if (args.Length != 1 || !CompileExpression(args[0]) || valueType != "string") {
                    return false;
                }
                code.Byte(59); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Console.Write" || name == "System.Console.WriteLine") {
                bool newline = name == "System.Console.WriteLine";
                if (args.Length == 0 && newline) {
                    if (!EmitLiteralWrite("", true)) { return false; }
                    valueType = "void"; return true;
                }
                if (args.Length != 1) { return false; }
                if (args[0].Kind() == IrExpression.KindLiteral() && args[0].LiteralKind() == "string") {
                    if (!EmitLiteralWrite(args[0].LiteralText(), newline)) { return false; }
                    valueType = "void"; return true;
                }
                if (!CompileExpression(args[0])) { return false; }
                if (valueType == "string") {
                    code.Byte(48); if (newline) { code.Byte(1); }
                    else { code.Byte(0); }
                    valueType = "void"; return code.IsValid();
                }
                int format = 0; if (newline) { format = 1; }
                if (valueType == "bool") { format = format + 2; }
                else if (!Numeric(valueType)) { return false; }
                code.Byte(32); code.Byte(format); valueType = "void"; return code.IsValid();
            }
            if (name == "System.Console.WriteBytes") {
                if (args.Length != 1 || !CompileExpression(args[0]) ||
                    valueType != "byte[]") { return false; }
                code.Byte(90); valueType = "void"; return code.IsValid();
            }
            if (name == "System.Australis.Terminal.Write" ||
                name == "System.Australis.Terminal.WriteLine") {
                if (args.Length != 1 || args[0].Kind() != IrExpression.KindLiteral() ||
                    args[0].LiteralKind() != "string") { return false; }
                if (!EmitLiteralWrite(args[0].LiteralText(),
                    name == "System.Australis.Terminal.WriteLine")) { return false; }
                valueType = "void"; return true;
            }
            if (name == "System.Australis.Terminal.ReadLine") {
                if (!OneNumber(args)) { return false; }
                int capacity = ParseInt(args[0].LiteralText());
                if (capacity < 1 || capacity > 65536) { return false; }
                code.Byte(3); EmitScratchAddress(); code.U32(capacity);
                if (capacity > scratchCapacity) { scratchCapacity = capacity; }
                valueType = "void"; return code.IsValid();
            }
            if (name == "System.Australis.Process.Run") {
                if (args.Length < 1 || args.Length > 3) { return false; }
                if (!CompileExpression(args[0]) || valueType != "string") { return false; }
                if (args.Length >= 2) {
                    if (!CompileExpression(args[1]) || valueType != "byte[]") { return false; }
                }
                if (args.Length == 3) {
                    if (!CompileExpression(args[2]) || valueType != "byte[]") { return false; }
                    code.Byte(83);
                } else if (args.Length == 2) { code.Byte(69); }
                else { code.Byte(68); }
                valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Process.Spawn") {
                if (args.Length != 1 || !CompileExpression(args[0]) ||
                    valueType != "string") { return false; }
                code.Byte(91); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Process.Wait") {
                if (args.Length != 1 || !CompileExpression(args[0]) ||
                    !Numeric(valueType)) { return false; }
                code.Byte(92); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Process.Ready") {
                if (args.Length != 0) { return false; }
                code.Byte(93); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Process.WaitReady") {
                if (args.Length != 2 || !CompileExpression(args[0]) ||
                    !Numeric(valueType) || !CompileExpression(args[1]) ||
                    !Numeric(valueType)) { return false; }
                code.Byte(94); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Process.Terminate") {
                if (args.Length != 1 || !CompileExpression(args[0]) ||
                    !Numeric(valueType)) { return false; }
                code.Byte(95); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Process.Sleep") {
                if (args.Length != 1 || !CompileExpression(args[0]) ||
                    !Numeric(valueType)) { return false; }
                code.Byte(96); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Channel.Open" ||
                name == "System.Australis.Channel.Wait") {
                if (args.Length != 2 || !CompileExpression(args[0]) ||
                    !Numeric(valueType) || !CompileExpression(args[1]) ||
                    !Numeric(valueType)) { return false; }
                if (name == "System.Australis.Channel.Open") { code.Byte(97); }
                else { code.Byte(101); }
                valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Channel.Accept" ||
                name == "System.Australis.Channel.Peer" ||
                name == "System.Australis.Channel.Close") {
                if (args.Length != 1 || !CompileExpression(args[0]) ||
                    !Numeric(valueType)) { return false; }
                if (name == "System.Australis.Channel.Accept") { code.Byte(98); }
                else if (name == "System.Australis.Channel.Peer") { code.Byte(102); }
                else { code.Byte(103); }
                valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Channel.Send") {
                if (args.Length != 3 || !CompileExpression(args[0]) ||
                    !Numeric(valueType) || !CompileExpression(args[1]) ||
                    !Numeric(valueType) || !CompileExpression(args[2]) ||
                    valueType != "byte[]") { return false; }
                code.Byte(99); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Channel.Receive") {
                if (args.Length != 2 || !CompileExpression(args[0]) ||
                    !Numeric(valueType) || !CompileExpression(args[1]) ||
                    valueType != "byte[]") { return false; }
                code.Byte(100); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Process.EnvironmentCount") {
                if (args.Length != 0) { return false; }
                code.Byte(84); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Process.EnvironmentEntry") {
                if (args.Length != 1 || !CompileExpression(args[0]) ||
                    !Numeric(valueType)) { return false; }
                code.Byte(85); valueType = "string"; return code.IsValid();
            }
            if (name == "System.Australis.Process.WorkingDirectory") {
                if (args.Length != 0) { return false; }
                code.Byte(86); valueType = "string"; return code.IsValid();
            }
            if (name == "System.Australis.Text.ByteAt") {
                if (args.Length != 2 || !CompileExpression(args[0]) ||
                    valueType != "string" || !CompileExpression(args[1]) ||
                    !Numeric(valueType)) { return false; }
                code.Byte(70); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Text.FromBytes") {
                if (args.Length != 2 || !CompileExpression(args[0]) ||
                    valueType != "byte[]" || !CompileExpression(args[1]) ||
                    !Numeric(valueType)) { return false; }
                code.Byte(71); valueType = "string"; return code.IsValid();
            }
            if (name == "System.Australis.Files.OpenReadHandle" ||
                name == "System.Australis.Files.OpenWriteHandle") {
                if (args.Length != 1 || !CompileExpression(args[0]) ||
                    valueType != "string") { return false; }
                if (name == "System.Australis.Files.OpenReadHandle") { code.Byte(73); }
                else { code.Byte(74); }
                valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Files.ReadHandle" ||
                name == "System.Australis.Files.WriteHandle") {
                if (args.Length != 3 || !CompileExpression(args[0]) ||
                    !Numeric(valueType) || !CompileExpression(args[1]) ||
                    valueType != "byte[]" || !CompileExpression(args[2]) ||
                    !Numeric(valueType)) { return false; }
                if (name == "System.Australis.Files.ReadHandle") { code.Byte(75); }
                else { code.Byte(76); }
                valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Files.CloseHandle") {
                if (args.Length != 1 || !CompileExpression(args[0]) ||
                    !Numeric(valueType)) { return false; }
                code.Byte(77); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Files.TruncateHandle") {
                if (args.Length != 2 || !CompileExpression(args[0]) ||
                    !Numeric(valueType) || !CompileExpression(args[1]) ||
                    !Numeric(valueType)) { return false; }
                code.Byte(78); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Files.DirectoryNameInto") {
                if (args.Length != 3 || !CompileExpression(args[0]) ||
                    valueType != "string" || !CompileExpression(args[1]) ||
                    !Numeric(valueType) || !CompileExpression(args[2]) ||
                    valueType != "byte[]") { return false; }
                code.Byte(79); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Terminal.WriteResult") {
                if (args.Length != 0) { return false; }
                code.Byte(4); EmitScratchAddress(); valueType = "void"; return code.IsValid();
            }
            if (name == "System.Australis.Terminal.Clear") {
                if (args.Length != 0) { return false; }
                code.Byte(72); valueType = "void"; return code.IsValid();
            }
            if (name == "System.Australis.Files.Open") {
                if (args.Length != 1 || args[0].Kind() != IrExpression.KindLiteral() ||
                    args[0].LiteralKind() != "string" || args[0].LiteralText().Length < 1 ||
                    args[0].LiteralText().Length > 255) { return false; }
                int offset = AddAscii(args[0].LiteralText(), false);
                if (offset < 0) { return false; }
                code.Byte(5); code.U32(DataBase() + offset); code.U32(args[0].LiteralText().Length);
                valueType = "void"; return code.IsValid();
            }
            if (name == "System.Australis.Files.Read") {
                if (!OneNumber(args)) { return false; }
                int capacity2 = ParseInt(args[0].LiteralText());
                if (capacity2 < 0 || capacity2 > 65536) { return false; }
                code.Byte(6); EmitScratchAddress(); code.U32(capacity2);
                if (capacity2 > scratchCapacity) { scratchCapacity = capacity2; }
                valueType = "void"; return code.IsValid();
            }
            if (name == "System.Australis.Files.Close") {
                if (args.Length != 0) { return false; }
                code.Byte(7); valueType = "void"; return code.IsValid();
            }
            if (name == "System.Australis.Files.StatKind" ||
                name == "System.Australis.Files.StatSize" ||
                name == "System.Australis.Files.StatId" ||
                name == "System.Australis.Files.StatCreated" ||
                name == "System.Australis.Files.StatModified" ||
                name == "System.Australis.Files.StatTimeFlags" ||
                name == "System.Australis.Files.StatAttributes") {
                if (args.Length != 1) { return false; }
                int selector = 0;
                if (name == "System.Australis.Files.StatSize") { selector = 1; }
                else if (name == "System.Australis.Files.StatId") { selector = 2; }
                else if (name == "System.Australis.Files.StatCreated") { selector = 3; }
                else if (name == "System.Australis.Files.StatModified") { selector = 4; }
                else if (name == "System.Australis.Files.StatTimeFlags") { selector = 5; }
                else if (name == "System.Australis.Files.StatAttributes") { selector = 6; }
                if (StringArgument(args, 0, 1)) {
                    code.Byte(33); code.Byte(selector);
                    if (!EmitPath(args[0].LiteralText())) { return false; }
                } else {
                    if (!CompileExpression(args[0]) || valueType != "string") { return false; }
                    code.Byte(51); code.Byte(selector);
                }
                valueType = "long";
                if (selector == 0 || selector == 5) { valueType = "int"; }
                return code.IsValid();
            }
            if (name == "System.Australis.Files.DirectoryCount") {
                if (args.Length != 1) { return false; }
                if (StringArgument(args, 0, 1)) {
                    code.Byte(34);
                    if (!EmitPath(args[0].LiteralText())) { return false; }
                } else {
                    if (!CompileExpression(args[0]) || valueType != "string") { return false; }
                    code.Byte(52);
                }
                valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Files.DirectoryName") {
                if (args.Length != 2) { return false; }
                bool literalDirectory = StringArgument(args, 0, 2);
                if (!literalDirectory &&
                    (!CompileExpression(args[0]) || valueType != "string")) { return false; }
                if (!CompileExpression(args[1]) || !Numeric(valueType)) { return false; }
                if (literalDirectory) {
                    code.Byte(35);
                    if (!EmitPath(args[0].LiteralText())) { return false; }
                } else { code.Byte(55); }
                EmitScratchAddress();
                if (scratchCapacity < 64) { scratchCapacity = 64; }
                valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Files.Create") {
                if (args.Length != 2) { return false; }
                if (StringArgument(args, 0, 2) && StringArgument(args, 1, 2)) {
                    code.Byte(36);
                    if (!EmitPath(args[0].LiteralText()) ||
                        !EmitText(args[1].LiteralText())) { return false; }
                } else {
                    if (!CompileExpression(args[0]) || valueType != "string" ||
                        !CompileExpression(args[1]) || valueType != "string") {
                        return false;
                    }
                    code.Byte(80);
                }
                valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Files.OpenRead" ||
                name == "System.Australis.Files.OpenWrite") {
                if (args.Length != 1) { return false; }
                int openMode = 0;
                if (name == "System.Australis.Files.OpenWrite") { openMode = 1; }
                if (StringArgument(args, 0, 1)) {
                    code.Byte(37); code.Byte(openMode);
                    if (!EmitPath(args[0].LiteralText())) { return false; }
                } else {
                    if (!CompileExpression(args[0]) || valueType != "string") { return false; }
                    code.Byte(50); code.Byte(openMode);
                }
                valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Files.Replace" ||
                name == "System.Australis.Files.Append") {
                if (!StringArgument(args, 0, 1)) { return false; }
                code.Byte(38);
                if (name == "System.Australis.Files.Append") { code.Byte(1); }
                else { code.Byte(0); }
                if (!EmitText(args[0].LiteralText())) { return false; }
                valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Files.Truncate") {
                if (args.Length != 1 || !CompileExpression(args[0]) ||
                    !Numeric(valueType)) { return false; }
                code.Byte(39); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Files.Delete" ||
                name == "System.Australis.Files.Mkdir" ||
                name == "System.Australis.Files.Rmdir") {
                if (args.Length != 1) { return false; }
                if (StringArgument(args, 0, 1)) { code.Byte(40); }
                else {
                    if (!CompileExpression(args[0]) || valueType != "string") { return false; }
                    code.Byte(81);
                }
                if (name == "System.Australis.Files.Delete") { code.Byte(0); }
                else if (name == "System.Australis.Files.Mkdir") { code.Byte(1); }
                else { code.Byte(2); }
                if (StringArgument(args, 0, 1) &&
                    !EmitPath(args[0].LiteralText())) { return false; }
                valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Files.Rename") {
                if (args.Length != 2) { return false; }
                if (StringArgument(args, 0, 2) && StringArgument(args, 1, 2)) {
                    code.Byte(41);
                    if (!EmitPath(args[0].LiteralText()) ||
                        !EmitPath(args[1].LiteralText())) { return false; }
                } else {
                    if (!CompileExpression(args[0]) || valueType != "string" ||
                        !CompileExpression(args[1]) || valueType != "string") {
                        return false;
                    }
                    code.Byte(82);
                }
                valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Files.Status") {
                if (args.Length != 0) { return false; }
                code.Byte(42); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Files.CloseChecked") {
                if (args.Length != 0) { return false; }
                code.Byte(43); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Files.ReadChecked") {
                if (!OneNumber(args)) { return false; }
                int checkedCapacity = ParseInt(args[0].LiteralText());
                if (checkedCapacity < 0 || checkedCapacity > 65536) { return false; }
                code.Byte(44); EmitScratchAddress(); code.U32(checkedCapacity);
                if (checkedCapacity > scratchCapacity) { scratchCapacity = checkedCapacity; }
                valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Files.ResultByte" ||
                name == "System.Australis.Files.ResultU32") {
                if (args.Length != 1 || !CompileExpression(args[0]) ||
                    !Numeric(valueType)) { return false; }
                code.Byte(53);
                if (name == "System.Australis.Files.ResultByte") {
                    code.Byte(1); valueType = "int";
                } else { code.Byte(4); valueType = "long"; }
                return code.IsValid();
            }
            if (name == "System.Australis.Files.ApiVersion") {
                if (args.Length != 0) { return false; }
                code.Byte(54); valueType = "int"; return code.IsValid();
            }
            if (name == "System.Australis.Files.WriteResult") {
                if (args.Length != 0) { return false; }
                code.Byte(4); EmitScratchAddress(); valueType = "void";
                return code.IsValid();
            }
            if (name == "System.Australis.Memory.StoreByte") {
                if (args.Length != 2 || args[0].Kind() != IrExpression.KindLiteral() ||
                    args[0].LiteralKind() != "number" || args[1].Kind() != IrExpression.KindLiteral() ||
                    args[1].LiteralKind() != "number") { return false; }
                int stored = ParseInt(args[1].LiteralText());
                if (stored < 0 || stored > 255) { return false; }
                code.Byte(8); code.U32(ParseInt(args[0].LiteralText())); code.Byte(stored);
                valueType = "void"; return code.IsValid();
            }
            if (name == "System.Australis.Process.Yield") {
                if (args.Length != 0) { return false; }
                code.Byte(9); valueType = "void"; return code.IsValid();
            }
            if (name == "System.Australis.SystemInfo.Query") {
                if (!OneNumber(args)) { return false; }
                int selector = ParseInt(args[0].LiteralText());
                if (selector < 0 || selector > 255) { return false; }
                code.Byte(63); code.Byte(selector);
                valueType = "int"; return code.IsValid();
            }
            string resolved = expression.ResolvedOwner() + ".";
            string methodName = ""; int dot = 0;
            while (dot < name.Length) {
                if (name[dot] == ".") { methodName = ""; }
                else { methodName = methodName + name[dot]; }
                dot = dot + 1;
            }
            resolved = resolved + methodName;
            int function = 0;
            while (function < functions.Length) {
                IrFunction candidate = functions[function];
                if (candidate.Name() == resolved &&
                    candidate.ParameterTypes().Length == args.Length &&
                    candidate.Declaration() != null && candidate.Declaration().IsStatic() &&
                    candidate.ReturnType() != "string[]") {
                    int argument = 0; bool compatible = true;
                    while (argument < args.Length) {
                        if (!CompileExpression(args[argument]) ||
                            !Compatible(valueType, candidate.ParameterTypes()[argument])) {
                            compatible = false; break;
                        }
                        argument = argument + 1;
                    }
                    if (!compatible) { return false; }
                    code.Byte(60); int patch = code.Position(); code.U32(0);
                    code.Byte(args.Length);
                    callPatches = AppendInt(callPatches, callCount, patch);
                    callTargets = AppendInt(callTargets, callCount, function);
                    callCount = callCount + 1;
                    valueType = candidate.ReturnType(); return code.IsValid();
                }
                function = function + 1;
            }
            return false;
        }

        private bool OneNumber(IrExpression[] args) {
            if (args.Length != 1) { return false; }
            if (args[0].Kind() != IrExpression.KindLiteral()) { return false; }
            return args[0].LiteralKind() == "number";
        }
        private bool StringArgument(IrExpression[] args, int index, int count) {
            return args.Length == count && args[index].Kind() == IrExpression.KindLiteral() &&
                args[index].LiteralKind() == "string";
        }
        private bool EmitPath(string path) {
            if (path.Length < 1 || path.Length > 255) { return false; }
            int offset = AddAscii(path, false);
            if (offset < 0) { return false; }
            code.U32(DataBase() + offset); code.U32(path.Length);
            return code.IsValid();
        }
        private bool EmitText(string contents) {
            int offset = AddAscii(contents, false);
            if (offset < 0) { return false; }
            code.U32(DataBase() + offset); code.U32(contents.Length);
            return code.IsValid();
        }
        private void EmitPush(int value) { code.Byte(11); code.U32((long)value); }
        private int EmitConditionalJump() { code.Byte(28); int patch = code.Position(); code.U32(0); return patch; }
        private int EmitJump() { code.Byte(10); int patch = code.Position(); code.U32(0); return patch; }
        private void EmitAbsoluteJump(int target) { code.Byte(10); code.U32(target); }
        private void PatchRange(int[] patches, int start, int end, int target) {
            int i = start; while (i < end) { code.Patch32(patches[i], target); i = i + 1; }
        }
        private void EmitScratchAddress() {
            int patch = code.Position(); code.U32(0);
            scratchPatches = AppendInt(scratchPatches, scratchPatchCount, patch);
            scratchPatchCount = scratchPatchCount + 1;
        }
        private void EmitHeapAddress() {
            int patch = code.Position(); code.U32(0);
            heapPatches = AppendInt(heapPatches, heapPatchCount, patch);
            heapPatchCount = heapPatchCount + 1; needsHeap = true;
        }
        private bool EmitLiteralWrite(string text, bool newline) {
            int offset = AddAscii(text, newline); if (offset < 0) { return false; }
            int count = text.Length; if (newline) { count = count + 2; }
            code.Byte(2); code.U32(DataBase() + offset); code.U32(count); return code.IsValid();
        }
        private int AddAscii(string text, bool newline) {
            int extra = 0; if (newline) { extra = 2; }
            if (!ascii.SupportsPayload(text) || dataLength + text.Length + extra > data.Length) { return -1; }
            int offset = dataLength; int i = 0;
            while (i < text.Length) {
                data[dataLength] = (byte)ascii.AsciiCode(text[i]); dataLength = dataLength + 1; i = i + 1;
            }
            if (newline) {
                data[dataLength] = (byte)13; data[dataLength + 1] = (byte)10; dataLength = dataLength + 2;
            }
            return offset;
        }
        private int AddLocal(string name, string type) {
            localNames = AppendString(localNames, localCount, name);
            localTypes = AppendString(localTypes, localCount, type);
            int result = localCount; localCount = localCount + 1; return result;
        }
        private int FindLocal(string name) {
            int i = localCount - 1;
            while (i >= 0) { if (localNames[i] == name) { return i; } i = i - 1; }
            return -1;
        }
        private bool Scalar(string type) {
            return type == "bool" || type == "string" || type == "byte[]" || Numeric(type);
        }
        private bool Numeric(string type) {
            return type == "byte" || type == "sbyte" || type == "short" || type == "ushort" ||
                type == "int" || type == "uint" || type == "long" || type == "ulong" ||
                type == "nint" || type == "nuint";
        }
        private bool Compatible(string left, string right) {
            return left == right || (Numeric(left) && Numeric(right));
        }
        private string QualifiedName(IrExpression expression) {
            if (expression == null) { return ""; }
            if (expression.Kind() == IrExpression.KindName()) { return expression.Name(); }
            if (expression.Kind() == IrExpression.KindMemberAccess()) {
                string left = QualifiedName(expression.Receiver());
                if (left != "") { return left + "." + expression.MemberName(); }
            }
            return "";
        }
        private int ParseInt(string text) {
            int start = 0; int radix = 10;
            if (text.Length >= 2 && text[0] == "0" && (text[1] == "x" || text[1] == "X")) {
                start = 2; radix = 16;
            }
            int value = 0; int i = start;
            while (i < text.Length) { value = value * radix + DigitValue(text[i]); i = i + 1; }
            return value;
        }
        private int DigitValue(string ch) {
            if (ch == "0") { return 0; } if (ch == "1") { return 1; }
            if (ch == "2") { return 2; } if (ch == "3") { return 3; }
            if (ch == "4") { return 4; } if (ch == "5") { return 5; }
            if (ch == "6") { return 6; } if (ch == "7") { return 7; }
            if (ch == "8") { return 8; } if (ch == "9") { return 9; }
            if (ch == "a" || ch == "A") { return 10; }
            if (ch == "b" || ch == "B") { return 11; }
            if (ch == "c" || ch == "C") { return 12; }
            if (ch == "d" || ch == "D") { return 13; }
            if (ch == "e" || ch == "E") { return 14; } return 15;
        }
        private string[] AppendString(string[] items, int count, string item) {
            string[] next = new string[count + 1]; int i = 0;
            while (i < count) { next[i] = items[i]; i = i + 1; }
            next[count] = item; return next;
        }
        private int[] AppendInt(int[] items, int count, int item) {
            int[] next = new int[count + 1]; int i = 0;
            while (i < count) { next[i] = items[i]; i = i + 1; }
            next[count] = item; return next;
        }
        private void Write32(byte[] output, int offset, long value) {
            int i = 0;
            while (i < 4) { output[offset + i] = (byte)(value % 256); value = value / 256; i = i + 1; }
        }
        private long Xor32(long left, long right) {
            long result = 0; long bit = 1;
            while (left > 0 || right > 0) {
                if (left % 2 != right % 2) { result = result + bit; }
                left = left / 2; right = right / 2; bit = bit * 2;
            }
            return result;
        }
        private long Crc32(byte[] bytes, int offset, int count) {
            long allOnes = 65535; allOnes = allOnes * 65536 + 65535;
            long polynomial = 39882; polynomial = polynomial * 100000 + 92384;
            long crc = allOnes; int i = 0;
            while (i < count) {
                crc = Xor32(crc, (long)bytes[offset + i]); int bit = 0;
                while (bit < 8) {
                    if (crc % 2 == 1) { crc = Xor32(crc / 2, polynomial); }
                    else { crc = crc / 2; }
                    bit = bit + 1;
                }
                i = i + 1;
            }
            return Xor32(crc, allOnes);
        }
    }
}
