using Hydrogen.Compiler.IR;

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

    // Function records are shared by resolution, reachable-body lowering and rel32 fixups.
    public class NativeFunction {
        private string owner;
        private IrMethod declaration;
        private int position;
        private bool needed;

        public NativeFunction(string inputOwner, IrMethod inputDeclaration) {
            owner = inputOwner;
            declaration = inputDeclaration;
            position = -1;
            needed = false;
        }
        public string Owner() { return owner; }
        public IrMethod Declaration() { return declaration; }
        public int Position() { return position; }
        public void SetPosition(int value) { position = value; }
        public bool Needed() { return needed; }
        public void Require() { needed = true; }
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
        private NativeFunction[] functions;
        private int functionCount;
        private int currentFunction;
        private int mainFunction;
        private int[] callPatchOffsets;
        private int[] callPatchTargets;
        private int callPatchCount;
        private IrModule module;
        private string[] localTypes;
        private int maxLocalCount;
        private int scopeStart;
        private string valueType;
        private string[] classNames;
        private IrClass[] classDeclarations;
        private int classCount;
        private string[] enumNames;
        private IrEnum[] enumDeclarations;
        private int enumCount;
        private string[] runtimeTargets;
        private int[] runtimePatches;
        private int runtimePatchCount;
        private bool receiverPushed;
        private bool directBaseCall;
        private bool addressReadOnly;
        private int loopStart;
        private int[] breakPatches;
        private int breakCount;
        private int[] continuePatches;
        private int continueCount;
        private string[] staticOwners;
        private string[] staticNames;
        private int staticCount;
        private string currentStaticOwner;

        public DirectImageResult Compile(IrModule input) {
            module = input;
            IrUnit root = module.Root();
            code = new X64Assembler();
            localNames = new string[0];
            localCount = 0;
            payloads = new string[0];
            payloadCount = 0;
            payloadPatchOffsets = new int[0];
            payloadPatchIndexes = new int[0];
            payloadPatchCount = 0;
            failure = "";

            classNames = new string[0];
            classDeclarations = new IrClass[0];
            classCount = 0;
            enumNames = new string[0];
            enumDeclarations = new IrEnum[0];
            enumCount = 0;
            runtimeTargets = new string[0];
            runtimePatches = new int[0];
            runtimePatchCount = 0;
            continuePatches = new int[0];
            continueCount = 0;
            staticOwners = new string[0];
            staticNames = new string[0];
            staticCount = 0;
            currentStaticOwner = "";
            functions = new NativeFunction[0];
            functionCount = 0;
            callPatchOffsets = new int[0];
            callPatchTargets = new int[0];
            callPatchCount = 0;

            CollectFunctions(root.Classes(), "");
            CollectEnums(root.Enums(), "");
            IrNamespace[] namespaces = root.Namespaces();
            int n = 0;
            while (n < namespaces.Length) {
                CollectFunctions(namespaces[n].Classes(), namespaces[n].Name());
                CollectEnums(namespaces[n].Enums(), namespaces[n].Name());
                n = n + 1;
            }
            CollectStaticFields();
            mainFunction = -1;
            int i = 0;
            while (i < functionCount) {
                IrMethod method = functions[i].Declaration();
                if (method.IsStatic() && method.Name() == "Main") {
                    if (mainFunction >= 0) { return Failed("multiple static Main methods"); }
                    mainFunction = i;
                }
                i = i + 1;
            }
            if (mainFunction < 0) { return Failed("no static Main method"); }
            IrMethod main = functions[mainFunction].Declaration();
            IrParameter[] mainParameters = main.Parameters();
            if (mainParameters.Length > 1) { return Failed("Main must have no parameters or one string[] parameter"); }
            if (mainParameters.Length == 1) {
                if (mainParameters[0].Type().DisplayName() != "string[]") {
                    return Failed("Main must have no parameters or one string[] parameter");
                }
            }
            // Linux entry stub: call Main, then turn its result into the process exit status.
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xe6); // mov r14, rsp: Linux initial stack
            EmitRuntime("rt_init"); // r15 owns heap state for the lifetime of the process
            if (staticCount > 0) {
                code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc7); code.Emit32(staticCount * 8);
                EmitRuntime("rt_alloc");
                code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xc5); // mov r13, rax: rooted static storage
            } else {
                code.EmitByte(0x45); code.EmitByte(0x31); code.EmitByte(0xed); // xor r13d, r13d
            }
            currentFunction = mainFunction;
            localNames = new string[0]; localTypes = new string[0]; localCount = 0; scopeStart = 0; loopStart = -1;
            int si = 0;
            while (si < staticCount) {
                IrField staticField = StaticDeclaration(si);
                if (staticField.Initializer() != null) {
                    currentStaticOwner = staticOwners[si];
                    if (!CompileExpression(staticField.Initializer())) { return Failed("static field " + staticOwners[si] + "." + staticNames[si] + ": " + failure); }
                    string staticType = ResolveType(staticField.Type().DisplayName(), staticOwners[si]);
                    if (!Assignable(valueType, staticType)) { return Failed("static field initializer type mismatch"); }
                    PrepareValue(staticType);
                    code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0x85); code.Emit32(si * 8); // mov [r13+offset], rax
                }
                si = si + 1;
            }
            currentStaticOwner = "";
            if (mainParameters.Length == 1) {
                EmitRuntime("rt_args");
                code.EmitByte(0x50);
            }
            EmitCall(mainFunction);
            EmitExitFromRax();

            // Compile the reachable call graph, including forward and mutually recursive edges.
            bool progress = true;
            while (progress) {
                progress = false;
                i = 0;
                while (i < functionCount) {
                    if (functions[i].Needed() && functions[i].Position() < 0) {
                        currentFunction = i;
                        if (!CompileFunction()) {
                            return Failed(functions[i].Owner() + "." + functions[i].Declaration().Name() + ": " + failure);
                        }
                        progress = true;
                    }
                    i = i + 1;
                }
            }
            i = 0;
            while (i < callPatchCount) {
                PatchRelative(callPatchOffsets[i], functions[callPatchTargets[i]].Position());
                i = i + 1;
            }
            NativeRuntimeEmitter runtime = new NativeRuntimeEmitter();
            int runtimeStart = code.Position();
            runtime.Emit(code);
            i = 0;
            while (i < runtimePatchCount) {
                int offset = runtime.Offset(runtimeTargets[i]);
                if (offset < 0) { return Failed("unknown native runtime helper: " + runtimeTargets[i]); }
                PatchRelative(runtimePatches[i], runtimeStart + offset);
                i = i + 1;
            }
            ElfImageBuilder imageBuilder = new ElfImageBuilder();
            int pi = 0;
            while (pi < payloads.Length) {
                if (!imageBuilder.SupportsPayload(payloads[pi])) { return Failed("non-ASCII string literals are not supported by the native backend"); }
                pi = pi + 1;
            }
            return new DirectImageResult(true, imageBuilder.BuildCodeAndData(code.ToArray(), payloads, payloadPatchOffsets, payloadPatchIndexes), "");
        }

        private DirectImageResult Failed(string message) {
            return new DirectImageResult(false, new byte[0], message);
        }

        private void CollectFunctions(IrClass[] classes, string namespaceName) {
            int c = 0;
            while (c < classes.Length) {
                string owner = classes[c].Name();
                if (namespaceName != "") { owner = namespaceName + "." + owner; }
                classNames = AppendString(classNames, classCount, owner);
                IrClass[] nextClasses = new IrClass[classCount + 1];
                int ci = 0;
                while (ci < classCount) { nextClasses[ci] = classDeclarations[ci]; ci = ci + 1; }
                nextClasses[classCount] = classes[c];
                classDeclarations = nextClasses;
                classCount = classCount + 1;
                IrMethod[] methods = classes[c].Methods();
                bool constructor = false;
                int mi = 0;
                while (mi < methods.Length) {
                    if (methods[mi].Name() == SimpleName(classes[c].Name())) { constructor = true; }
                    mi = mi + 1;
                }
                if (!constructor && !classes[c].IsInterface()) {
                    IrMethod[] withConstructor = new IrMethod[methods.Length + 1];
                    mi = 0;
                    while (mi < methods.Length) { withConstructor[mi] = methods[mi]; mi = mi + 1; }
                    withConstructor[mi] = new IrMethod(SimpleName(classes[c].Name()), false, false, false, new IrType("void"), new IrParameter[0], IrStatement.Block(new IrStatement[0]));
                    methods = withConstructor;
                }
                int m = 0;
                while (m < methods.Length) {
                    NativeFunction[] next = new NativeFunction[functionCount + 1];
                    int i = 0;
                    while (i < functionCount) { next[i] = functions[i]; i = i + 1; }
                    next[functionCount] = new NativeFunction(owner, methods[m]);
                    functions = next;
                    functionCount = functionCount + 1;
                    m = m + 1;
                }
                c = c + 1;
            }
        }

        private void CollectEnums(IrEnum[] declarations, string namespaceName) {
            int i = 0;
            while (i < declarations.Length) {
                string name = declarations[i].Name();
                if (namespaceName != "") { name = namespaceName + "." + name; }
                enumNames = AppendString(enumNames, enumCount, name);
                IrEnum[] next = new IrEnum[enumCount + 1];
                int j = 0;
                while (j < enumCount) { next[j] = enumDeclarations[j]; j = j + 1; }
                next[enumCount] = declarations[i];
                enumDeclarations = next;
                enumCount = enumCount + 1;
                i = i + 1;
            }
        }

        private void CollectStaticFields() {
            int c = 0;
            while (c < classCount) {
                IrField[] fields = classDeclarations[c].Fields(); int f = 0;
                while (f < fields.Length) {
                    if (fields[f].IsStatic()) {
                        staticOwners = AppendString(staticOwners, staticCount, classNames[c]);
                        staticNames = AppendString(staticNames, staticCount, fields[f].Name());
                        staticCount = staticCount + 1;
                    }
                    f = f + 1;
                }
                c = c + 1;
            }
        }

        private IrField StaticDeclaration(int index) {
            int ci = ClassIndex(staticOwners[index]);
            IrField[] fields = classDeclarations[ci].Fields(); int i = 0;
            while (i < fields.Length) { if (fields[i].Name() == staticNames[index]) { return fields[i]; } i = i + 1; }
            return null;
        }

        private bool ValidateSignature(IrMethod method) {
            string owner = functions[currentFunction].Owner();
            if (!SupportedType(ResolveType(method.ReturnType().DisplayName(), owner), true)) {
                failure = "unsupported native method return type"; return false;
            }
            IrParameter[] parameters = method.Parameters();
            int i = 0;
            while (i < parameters.Length) {
                if (!SupportedType(ResolveType(parameters[i].Type().DisplayName(), owner), false)) {
                    failure = "unsupported native method parameter type"; return false;
                }
                i = i + 1;
            }
            return true;
        }

        private bool CompileFunction() {
            NativeFunction function = functions[currentFunction];
            IrMethod method = function.Declaration();
            if (method.Body() == null) { failure = "interface dispatch is not supported by the native backend"; return false; }
            // Main receives the managed argv array created by the Linux entry stub.
            if (currentFunction != mainFunction) {
                if (!ValidateSignature(method)) { return false; }
            } else {
                string mainReturn = method.ReturnType().DisplayName();
                if (mainReturn != "int" && mainReturn != "void") { failure = "Main must return int or void"; return false; }
            }
            if (method.ReturnType().DisplayName() != "void" && !AlwaysReturns(method.Body())) {
                failure = "not all paths return a value"; return false;
            }
            function.SetPosition(code.Position());
            localNames = new string[0];
            localTypes = new string[0];
            localCount = 0;
            maxLocalCount = 0;
            scopeStart = 0;
            loopStart = -1;
            breakPatches = new int[0];
            breakCount = 0;
            code.EmitByte(0x55); // push rbp (callee preserves caller's frame)
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xe5); // mov rbp, rsp
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xec);
            int framePatch = code.Position();
            code.Emit32(0); // patch sub rsp, frameBytes after lowering locals
            // Uninitialized slots must not retain pointers from previous calls
            // when the conservative runtime scans this active frame.
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xe7); // mov rdi, rsp
            code.EmitByte(0xb9);
            int clearPatch = code.Position();
            code.Emit32(0); // mov ecx, frameSlots
            code.EmitByte(0x31); code.EmitByte(0xc0); // xor eax, eax
            code.EmitByte(0xf3); code.EmitByte(0x48); code.EmitByte(0xab); // rep stosq
            {
                IrParameter[] parameters = method.Parameters();
                if (!method.IsStatic()) {
                    int thisSlot = AddLocal("this", function.Owner());
                    code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x85);
                    code.Emit32(16 + 8 * parameters.Length);
                    EmitStoreLocal(thisSlot);
                }
                int i = 0;
                while (i < parameters.Length) {
                    int slot = AddLocal(parameters[i].Name(), ResolveType(parameters[i].Type().DisplayName(), function.Owner()));
                    if (slot < 0) { return false; }
                    code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x85);
                    code.Emit32(16 + 8 * (parameters.Length - 1 - i)); // caller pushed args left to right
                    EmitStoreLocal(slot);
                    i = i + 1;
                }
            }
            if (method.Name() == SimpleName(function.Owner()) && !method.IsStatic()) {
                if (!CompileConstructorInitializer(function.Owner(), method)) { return false; }
                int typeIndex = ClassIndex(function.Owner());
                IrField[] fields = classDeclarations[typeIndex].Fields();
                int fi = 0;
                int instanceField = 0;
                if (classDeclarations[typeIndex].BaseType() != "") { instanceField = InstanceFieldCount(classDeclarations[typeIndex].BaseType()); }
                while (fi < fields.Length && method.ConstructorInitializerKind() != "this") {
                    if (!fields[fi].IsStatic() && fields[fi].Initializer() != null) {
                        EmitLoadLocal(FindLocal("this"));
                        code.EmitByte(0x50);
                        if (!CompileExpression(fields[fi].Initializer())) { return false; }
                        if (!Assignable(valueType, ResolveType(fields[fi].Type().DisplayName(), function.Owner()))) {
                            failure = "native field initializer type mismatch"; return false;
                        }
                        PrepareValue(ResolveType(fields[fi].Type().DisplayName(), function.Owner()));
                        code.EmitByte(0x59);
                        EmitFieldStore(instanceField);
                    }
                    if (!fields[fi].IsStatic()) { instanceField = instanceField + 1; }
                    fi = fi + 1;
                }
            }
            if (!CompileStatement(method.Body())) { return false; }
            EmitMoveRaxImmediate(0); // void fallthrough
            EmitReturn();
            code.Patch32(framePatch, maxLocalCount * 8);
            code.Patch32(clearPatch, maxLocalCount);
            return true;
        }

        private bool AlwaysReturns(IrStatement statement) {
            if (statement == null) { return false; }
            if (statement.Kind() == IrStatement.KindReturnStatement()) { return true; }
            if (statement.Kind() == IrStatement.KindBlock()) {
                IrStatement[] items = statement.Statements();
                int i = 0;
                while (i < items.Length) {
                    if (AlwaysReturns(items[i])) { return true; }
                    i = i + 1;
                }
            }
            if (statement.Kind() == IrStatement.KindIfStatement()) {
                return AlwaysReturns(statement.ThenStatement()) && AlwaysReturns(statement.ElseStatement());
            }
            return false;
        }

        private void EmitCall(int target) {
            functions[target].Require();
            code.EmitByte(0xe8); // call rel32, patched after all reachable bodies are emitted
            callPatchOffsets = AppendInt(callPatchOffsets, callPatchCount, code.Position());
            callPatchTargets = AppendInt(callPatchTargets, callPatchCount, target);
            callPatchCount = callPatchCount + 1;
            code.Emit32(0);
        }

        private void EmitReturn() {
            code.EmitByte(0xc9); // leave: discard frame/temporaries, restore caller rbp
            code.EmitByte(0xc3); // ret: return to the caller, not the Linux exit syscall
        }

        private bool CompileStatement(IrStatement statement) {
            if (statement == null) { return true; }
            int kind = statement.Kind();
            if (kind == IrStatement.KindBlock()) {
                int savedCount = localCount;
                int savedScope = scopeStart;
                scopeStart = localCount;
                IrStatement[] items = statement.Statements();
                int i = 0;
                while (i < items.Length) {
                    if (!CompileStatement(items[i])) { return false; }
                    i = i + 1;
                }
                i = savedCount;
                while (i < localCount) {
                    EmitMoveRaxImmediate(0);
                    EmitStoreLocal(i);
                    i = i + 1;
                }
                localCount = savedCount;
                scopeStart = savedScope;
                return true;
            }
            if (kind == IrStatement.KindVariableDeclaration()) {
                string type = ResolveType(statement.Type().DisplayName(), functions[currentFunction].Owner());
                if (statement.Initializer() == null) {
                    EmitMoveRaxImmediate(0);
                    valueType = type;
                } else if (!CompileExpression(statement.Initializer())) { return false; }
                if (type == "var") { type = valueType; }
                if (!SupportedType(type, false)) {
                    failure = "unsupported native local type: " + type; return false;
                }
                if (!Assignable(valueType, type)) { failure = "native local initializer type mismatch"; return false; }
                PrepareValue(type);
                int slot = AddLocal(statement.Name(), type);
                if (slot < 0) { return false; }
                EmitStoreLocal(slot);
                return true;
            }
            if (kind == IrStatement.KindExpressionStatement()) {
                return CompileExpression(statement.Expression());
            }
            if (kind == IrStatement.KindReturnStatement()) {
                string returnType = ResolveType(functions[currentFunction].Declaration().ReturnType().DisplayName(), functions[currentFunction].Owner());
                if (statement.Expression() == null) {
                    if (returnType != "void") { failure = "return value required"; return false; }
                    EmitMoveRaxImmediate(0);
                } else {
                    if (!CompileExpression(statement.Expression())) { return false; }
                    if (!Assignable(valueType, returnType) || returnType == "void") {
                        failure = "native return type mismatch"; return false;
                    }
                    PrepareValue(returnType);
                }
                EmitReturn();
                return true;
            }
            if (kind == IrStatement.KindIfStatement()) {
                if (!CompileExpression(statement.Condition())) { return false; }
                if (valueType != "bool") { failure = "native condition must be bool"; return false; }
                int elsePatch = EmitJumpIfZero();
                if (!CompileStatement(statement.ThenStatement())) { return false; }
                int endPatch = EmitJump();
                PatchRelative(elsePatch, code.Position());
                if (!CompileStatement(statement.ElseStatement())) { return false; }
                PatchRelative(endPatch, code.Position());
                return true;
            }
            if (kind == IrStatement.KindWhileStatement()) {
                int previousLoop = loopStart;
                int savedBreaks = breakCount;
                int conditionPosition = code.Position();
                loopStart = conditionPosition;
                if (!CompileExpression(statement.Condition())) { return false; }
                if (valueType != "bool") { failure = "native condition must be bool"; return false; }
                int exitPatch = EmitJumpIfZero();
                if (!CompileStatement(statement.Body())) { return false; }
                int backPatch = EmitJump();
                PatchRelative(backPatch, conditionPosition);
                PatchRelative(exitPatch, code.Position());
                int bi = savedBreaks;
                while (bi < breakCount) { PatchRelative(breakPatches[bi], code.Position()); bi = bi + 1; }
                breakCount = savedBreaks;
                loopStart = previousLoop;
                return true;
            }
            if (kind == IrStatement.KindForStatement()) {
                int savedCount = localCount;
                int savedScope = scopeStart;
                scopeStart = localCount;
                if (!CompileStatement(statement.ForInitializer())) { return false; }

                int previousLoop = loopStart;
                int savedBreaks = breakCount;
                int savedContinues = continueCount;
                int conditionPosition = code.Position();
                loopStart = -2;
                if (!CompileExpression(statement.Condition())) { return false; }
                if (valueType != "bool") { failure = "native condition must be bool"; return false; }
                int exitPatch = EmitJumpIfZero();
                if (!CompileStatement(statement.Body())) { return false; }

                int incrementPosition = code.Position();
                int ci = savedContinues;
                while (ci < continueCount) { PatchRelative(continuePatches[ci], incrementPosition); ci = ci + 1; }
                continueCount = savedContinues;
                if (statement.ForIncrement() != null) {
                    if (!CompileExpression(statement.ForIncrement())) { return false; }
                }
                int backPatch = EmitJump();
                PatchRelative(backPatch, conditionPosition);
                PatchRelative(exitPatch, code.Position());
                int bi = savedBreaks;
                while (bi < breakCount) { PatchRelative(breakPatches[bi], code.Position()); bi = bi + 1; }
                breakCount = savedBreaks;
                loopStart = previousLoop;

                int clear = savedCount;
                while (clear < localCount) { EmitMoveRaxImmediate(0); EmitStoreLocal(clear); clear = clear + 1; }
                localCount = savedCount;
                scopeStart = savedScope;
                return true;
            }
            if (kind == IrStatement.KindBreakStatement() || kind == IrStatement.KindContinueStatement()) {
                if (loopStart == -1) { failure = "break or continue outside native loop"; return false; }
                int patch = EmitJump();
                if (kind == IrStatement.KindContinueStatement() && loopStart == -2) {
                    continuePatches = AppendInt(continuePatches, continueCount, patch);
                    continueCount = continueCount + 1;
                } else if (kind == IrStatement.KindContinueStatement()) { PatchRelative(patch, loopStart); }
                else { breakPatches = AppendInt(breakPatches, breakCount, patch); breakCount = breakCount + 1; }
                return true;
            }
            failure = "unsupported statement in direct native backend";
            return false;
        }

        private bool CompileExpression(IrExpression expression) {
            if (expression == null) {
                EmitMoveRaxImmediate(0);
                return true;
            }
            int kind = expression.Kind();
            if (kind == IrExpression.KindLiteral()) {
                if (expression.LiteralKind() == "number") {
                    EmitMoveRaxImmediate(ParseInt(expression.LiteralText()));
                    valueType = "int";
                    return true;
                }
                if (expression.LiteralKind() == "bool") {
                    if (expression.LiteralText() == "true") { EmitMoveRaxImmediate(1); }
                    else { EmitMoveRaxImmediate(0); }
                    valueType = "bool";
                    return true;
                }
                if (expression.LiteralKind() == "string") {
                    EmitLiteral(expression.LiteralText());
                    valueType = "string";
                    return true;
                }
                if (expression.LiteralKind() == "null") {
                    EmitMoveRaxImmediate(0); valueType = "null"; return true;
                }
                failure = "unsupported native literal"; return false;
            }
            if (kind == IrExpression.KindName()) {
                if (expression.Name() == "base") {
                    int thisSlot = FindLocal("this");
                    if (thisSlot < 0) { failure = "base requires an instance receiver"; return false; }
                    EmitLoadLocal(thisSlot);
                    int ownerIndex = ClassIndex(functions[currentFunction].Owner());
                    if (ownerIndex < 0 || classDeclarations[ownerIndex].BaseType() == "") { failure = "base requires a base class"; return false; }
                    valueType = classDeclarations[ownerIndex].BaseType(); return true;
                }
                int slot = FindLocal(expression.Name());
                if (slot < 0) {
                    if (CompileFieldAddress(null, expression.Name(), expression.ResolvedOwner())) {
                        code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x00);
                        return true;
                    }
                    failure = "unknown native local or field '" + expression.Name() + "'";
                    return false;
                }
                EmitLoadLocal(slot);
                valueType = localTypes[slot];
                return true;
            }
            if (kind == IrExpression.KindAssignment()) {
                return CompileAssignment(expression);
            }
            if (kind == IrExpression.KindMemberAccess()) {
                if (CompileEnum(expression)) { return true; }
                if (!CompileFieldAddress(expression.Receiver(), expression.MemberName(), expression.ResolvedOwner())) { return false; }
                code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x00);
                return true;
            }
            if (kind == IrExpression.KindIndex()) {
                if (!CompileExpression(expression.Receiver())) { return false; }
                string receiverType = valueType;
                code.EmitByte(0x50);
                if (!CompileExpression(expression.Index())) { return false; }
                if (!Numeric(valueType)) { failure = "native index must be integral"; return false; }
                code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc6);
                code.EmitByte(0x5f);
                if (receiverType == "string") { EmitRuntime("rt_char"); valueType = "string"; return true; }
                if (!IsArray(receiverType)) { failure = "native indexing requires array or string"; return false; }
                EmitRuntime("rt_index");
                code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x00);
                valueType = ElementType(receiverType);
                return true;
            }
            if (kind == IrExpression.KindArrayCreation()) {
                string type = ResolveType(expression.Type().DisplayName(), functions[currentFunction].Owner());
                if (!SupportedType(type, false)) { failure = "unsupported native array element type"; return false; }
                if (!CompileExpression(expression.Size())) { return false; }
                if (!Numeric(valueType)) { failure = "native array size must be integral"; return false; }
                MoveRdiRax(); EmitRuntime("rt_array"); valueType = type + "[]"; return true;
            }
            if (kind == IrExpression.KindObjectCreation()) { return CompileObject(expression); }
            if (kind == IrExpression.KindCast()) {
                string castType = ResolveType(expression.CastType().DisplayName(), functions[currentFunction].Owner());
                if (!CompileExpression(expression.CastExpression())) { return false; }
                if (!Numeric(valueType) || !Numeric(castType)) { failure = "unsupported native cast"; return false; }
                NormalizeRax(castType);
                valueType = castType; return true;
            }
            if (kind == IrExpression.KindSizeOf()) {
                string sizedType = ResolveType(expression.SizeOfType().DisplayName(), functions[currentFunction].Owner());
                int size = TypeSize(sizedType);
                if (size < 0) { failure = "sizeof requires an unmanaged primitive, enum, or unmanaged struct type"; return false; }
                EmitMoveRaxImmediate(size); valueType = "nuint"; return true;
            }
            if (kind == IrExpression.KindUnary()) {
                if (!CompileExpression(expression.UnaryOperand())) { return false; }
                if (expression.UnaryOperatorKind() == IrOperator.MinusToken()) {
                    if (!Numeric(valueType)) { failure = "native unary minus requires an integral operand"; return false; }
                    code.EmitByte(0x48); code.EmitByte(0xf7); code.EmitByte(0xd8); // neg rax
                    NormalizeRax(valueType);
                    return true;
                }
                if (expression.UnaryOperatorKind() == IrOperator.PlusToken()) {
                    if (!Numeric(valueType)) { failure = "native unary plus requires an integral operand"; return false; }
                    return true;
                }
                if (expression.UnaryOperatorKind() == IrOperator.BangToken()) {
                    if (valueType != "bool") { failure = "native logical negation requires bool"; return false; }
                    code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xc0); // test rax, rax
                    code.EmitByte(0x0f); code.EmitByte(0x94); code.EmitByte(0xc0); // sete al
                    code.EmitByte(0x48); code.EmitByte(0x0f); code.EmitByte(0xb6); code.EmitByte(0xc0); // movzx rax, al
                    return true;
                }
                failure = "unsupported unary operator";
                return false;
            }
            if (kind == IrExpression.KindBinary()) {
                return CompileBinary(expression);
            }
            if (kind == IrExpression.KindInvocation()) {
                return CompileInvocation(expression);
            }
            failure = "unsupported expression in direct native backend";
            return false;
        }

        private bool CompileBinary(IrExpression expression) {
            int op = expression.OperatorKind();
            if (op == IrOperator.AmpersandAmpersandToken() || op == IrOperator.PipePipeToken()) {
                return CompileLogical(expression);
            }
            if (!CompileExpression(expression.Left())) { return false; }
            string leftType = valueType;
            code.EmitByte(0x50); // push rax
            if (!CompileExpression(expression.Right())) { return false; }
            string rightType = valueType;
            code.EmitByte(0x59); // pop rcx (left), rax is right
            if (op == IrOperator.PlusToken() && (leftType == "string" || valueType == "string")) {
                if (leftType != "string") {
                    code.EmitByte(0x50);
                    code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xcf);
                    if (!ConvertString(leftType)) { return false; }
                    code.EmitByte(0x5e); MoveRdiRax();
                } else {
                    code.EmitByte(0x51);
                    MoveRdiRax();
                    if (!ConvertString(rightType)) { return false; }
                    code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc6); code.EmitByte(0x5f);
                }
                EmitRuntime("rt_concat"); valueType = "string"; return true;
            }
            if ((op == IrOperator.EqualsEqualsToken() || op == IrOperator.BangEqualsToken()) &&
                (leftType == "string" || valueType == "string")) {
                if (!Assignable(leftType, "string") || !Assignable(valueType, "string")) { failure = "native string comparison type mismatch"; return false; }
                code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xcf);
                code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc6);
                EmitRuntime("rt_equal");
                if (op == IrOperator.BangEqualsToken()) { code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xf0); code.EmitByte(1); }
                valueType = "bool"; return true;
            }
            if (!Assignable(leftType, rightType) && !Assignable(rightType, leftType)) {
                failure = "native binary operand type mismatch"; return false;
            }
            if (op != IrOperator.EqualsEqualsToken() && op != IrOperator.BangEqualsToken() && !Numeric(rightType)) {
                failure = "native arithmetic and ordering require integral operands"; return false;
            }
            string resultType = expression.ResultType();
            if (resultType == "") { resultType = leftType; }
            if (op == IrOperator.PlusToken()) {
                code.EmitByte(0x48); code.EmitByte(0x01); code.EmitByte(0xc8); // add rax, rcx
                NormalizeRax(resultType); valueType = resultType;
                return true;
            }
            if (op == IrOperator.MinusToken()) {
                code.EmitByte(0x48); code.EmitByte(0x29); code.EmitByte(0xc1); // sub rcx, rax
                code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc8); // mov rax, rcx
                NormalizeRax(resultType); valueType = resultType;
                return true;
            }
            if (op == IrOperator.StarToken()) {
                code.EmitByte(0x48); code.EmitByte(0x0f); code.EmitByte(0xaf); code.EmitByte(0xc8); // imul rcx, rax
                code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc8); // mov rax, rcx
                NormalizeRax(resultType); valueType = resultType;
                return true;
            }
            if (op == IrOperator.SlashToken() || op == IrOperator.PercentToken()) {
                code.EmitByte(0x48); code.EmitByte(0x91); // xchg rax, rcx
                if (UnsignedOperation(leftType, rightType)) {
                    code.EmitByte(0x31); code.EmitByte(0xd2); // xor edx, edx
                    code.EmitByte(0x48); code.EmitByte(0xf7); code.EmitByte(0xf1); // div rcx
                } else {
                    code.EmitByte(0x48); code.EmitByte(0x99); // cqo: signed dividend rdx:rax
                    code.EmitByte(0x48); code.EmitByte(0xf7); code.EmitByte(0xf9); // idiv rcx
                }
                if (op == IrOperator.PercentToken()) {
                    code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xd0); // mov rax, rdx
                }
                NormalizeRax(resultType); valueType = resultType;
                return true;
            }
            if (op == IrOperator.EqualsEqualsToken() || op == IrOperator.BangEqualsToken() ||
                op == IrOperator.LessToken() || op == IrOperator.LessEqualsToken() ||
                op == IrOperator.GreaterToken() || op == IrOperator.GreaterEqualsToken()) {
                code.EmitByte(0x48); code.EmitByte(0x39); code.EmitByte(0xc1); // cmp rcx, rax
                code.EmitByte(0x0f);
                if (op == IrOperator.EqualsEqualsToken()) { code.EmitByte(0x94); }
                if (op == IrOperator.BangEqualsToken()) { code.EmitByte(0x95); }
                if (op == IrOperator.LessToken()) { if (UnsignedOperation(leftType, rightType)) { code.EmitByte(0x92); } else { code.EmitByte(0x9c); } }
                if (op == IrOperator.LessEqualsToken()) { if (UnsignedOperation(leftType, rightType)) { code.EmitByte(0x96); } else { code.EmitByte(0x9e); } }
                if (op == IrOperator.GreaterToken()) { if (UnsignedOperation(leftType, rightType)) { code.EmitByte(0x97); } else { code.EmitByte(0x9f); } }
                if (op == IrOperator.GreaterEqualsToken()) { if (UnsignedOperation(leftType, rightType)) { code.EmitByte(0x93); } else { code.EmitByte(0x9d); } }
                valueType = "bool";
                code.EmitByte(0xc0); // setcc al
                code.EmitByte(0x48); code.EmitByte(0x0f); code.EmitByte(0xb6); code.EmitByte(0xc0); // movzx rax, al
                return true;
            }
            failure = "unsupported binary operator";
            return false;
        }

        private bool CompileLogical(IrExpression expression) {
            if (!CompileExpression(expression.Left())) { return false; }
            if (valueType != "bool") { failure = "native logical operands must be bool"; return false; }
            int shortPatch = EmitJumpIfZero();
            if (expression.OperatorKind() == IrOperator.PipePipeToken()) {
                // False evaluates the right operand; true skips it with rax unchanged.
                int truePatch = EmitJump();
                PatchRelative(shortPatch, code.Position());
                if (!CompileExpression(expression.Right())) { return false; }
                if (valueType != "bool") { failure = "native logical operands must be bool"; return false; }
                PatchRelative(truePatch, code.Position());
            } else {
                if (!CompileExpression(expression.Right())) { return false; }
                if (valueType != "bool") { failure = "native logical operands must be bool"; return false; }
                PatchRelative(shortPatch, code.Position());
            }
            valueType = "bool";
            return true;
        }

        private bool CompileInvocation(IrExpression expression) {
            IrExpression[] arguments = expression.Arguments();
            string intrinsic = QualifiedName(expression.Target());
            if (intrinsic == "System.Console.WriteLine" || intrinsic == "System.Console.Write") {
                if (arguments.Length > 1 || (arguments.Length == 0 && intrinsic == "System.Console.Write")) {
                    failure = "native console output requires one value"; return false;
                }
                if (arguments.Length == 0) { EmitLiteral(""); valueType = "string"; }
                else { if (!CompileExpression(arguments[0])) { return false; } }
                MoveRdiRax();
                if (!ConvertString(valueType)) { return false; }
                MoveRdiRax();
                int newline = 0;
                if (intrinsic == "System.Console.WriteLine") { newline = 1; }
                code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc6); code.Emit32(newline);
                EmitRuntime("rt_print"); valueType = "void"; return true;
            }
            if (intrinsic == "System.IO.File.Exists") { return RuntimeCall(expression, "rt_exists", "string", "", "bool"); }
            if (intrinsic == "System.IO.File.ReadAllText") { return RuntimeCall(expression, "rt_read_text", "string", "", "string"); }
            if (intrinsic == "System.IO.File.ReadAllBytes") { return RuntimeCall(expression, "rt_read_bytes", "string", "", "byte[]"); }
            if (intrinsic == "System.IO.File.WriteAllText") { return RuntimeCall(expression, "rt_write_text", "string", "string", "void"); }
            if (intrinsic == "System.IO.File.WriteAllBytes") { return RuntimeCall(expression, "rt_write_bytes", "string", "byte[]", "void"); }
            if (intrinsic == "System.Convert.ToInt32") { return RuntimeCall(expression, "rt_to_int", "string", "", "int"); }
            if (intrinsic == "System.Runtime.GC.Collect") { return RuntimeCall(expression, "rt_gc", "", "", "void"); }
            if (intrinsic == "System.Runtime.GC.GetAllocatedBytes") { return RuntimeCall(expression, "rt_heapbytes", "", "", "int"); }
            if (RootName(intrinsic) == "System") {
                failure = "unsupported native runtime intrinsic: " + intrinsic; return false;
            }
            int target = ResolveFunction(expression);
            if (target < 0) { return false; }
            bool hasReceiver = receiverPushed;
            IrMethod method = functions[target].Declaration();
            IrParameter[] parameters = method.Parameters();
            if (parameters.Length != arguments.Length) { failure = "wrong argument count calling '" + method.Name() + "'"; return false; }
            int i = 0;
            while (i < arguments.Length) {
                string type = ResolveType(parameters[i].Type().DisplayName(), functions[target].Owner());
                if (!SupportedType(type, false)) { failure = "unsupported native method parameter type"; return false; }
                if (!CompileExpression(arguments[i])) { return false; }
                if (!Assignable(valueType, type)) { failure = "argument type mismatch calling '" + method.Name() + "'"; return false; }
                PrepareValue(type);
                code.EmitByte(0x50);
                i = i + 1;
            }
            int targetOwnerIndex = ClassIndex(functions[target].Owner());
            bool interfaceCall = targetOwnerIndex >= 0 && classDeclarations[targetOwnerIndex].IsInterface();
            if ((method.IsVirtual() || method.IsOverride() || interfaceCall) && !directBaseCall) { EmitVirtualCall(target, arguments.Length); }
            else { EmitCall(target); }
            int slots = arguments.Length;
            if (hasReceiver) { slots = slots + 1; }
            DropSlots(slots);
            valueType = ResolveType(method.ReturnType().DisplayName(), functions[target].Owner());
            return true;
        }

        private int ResolveFunction(IrExpression call) {
            receiverPushed = false;
            directBaseCall = false;
            IrExpression target = call.Target();
            if (target == null) { failure = "unsupported native call target"; return -1; }
            string owner = functions[currentFunction].Owner();
            if (target.ResolvedOwner() != "") { owner = target.ResolvedOwner(); }
            string name = "";
            bool explicitReceiver = false;
            if (target.Kind() == IrExpression.KindName()) { name = target.Name(); }
            else if (target.Kind() == IrExpression.KindMemberAccess()) {
                IrExpression receiver = target.Receiver();
                if (receiver.Kind() == IrExpression.KindName() && receiver.Name() == "base") { directBaseCall = true; }
                owner = target.ResolvedOwner();
                int declared = FindFunction(owner, target.MemberName(), call.ResolvedSignature());
                if (declared < 0) { return -1; }
                if (!functions[declared].Declaration().IsStatic()) {
                    if (!CompileExpression(receiver)) { return -1; }
                    MoveRdiRax(); EmitRuntime("rt_check"); code.EmitByte(0x50);
                    explicitReceiver = true;
                }
                name = target.MemberName();
            } else { failure = "unsupported native call target"; return -1; }
            int found = FindFunction(owner, name, call.ResolvedSignature());
            if (found < 0) { return -1; }
            IrMethod method = functions[found].Declaration();
            if (!method.IsStatic()) {
                if (!explicitReceiver) {
                    int slot = FindLocal("this");
                    if (slot < 0) { failure = "instance method requires an object receiver"; return -1; }
                    EmitLoadLocal(slot); code.EmitByte(0x50);
                }
                receiverPushed = true;
            } else if (explicitReceiver) { failure = "static method requires a type receiver"; return -1; }
            return found;
        }

        private string Signature(IrMethod candidate) {
            string result = candidate.Name() + "("; int i = 0;
            while (i < candidate.Parameters().Length) {
                if (i > 0) { result = result + ","; }
                result = result + candidate.Parameters()[i].Type().DisplayName(); i = i + 1;
            }
            return result + ")";
        }

        private int FindFunction(string owner, string name, string signature) {
            int i = 0;
            while (i < functionCount) {
                if (functions[i].Owner() == owner && functions[i].Declaration().Name() == name) {
                    if (signature == "" || Signature(functions[i].Declaration()) == signature) { return i; }
                }
                i = i + 1;
            }
            int ci = ClassIndex(owner);
            if (ci >= 0 && classDeclarations[ci].BaseType() != "") {
                return FindFunction(classDeclarations[ci].BaseType(), name, signature);
            }
            if (ci >= 0) {
                int ii = 0;
                while (ii < classDeclarations[ci].InterfaceTypes().Length) {
                    int inherited = FindFunction(classDeclarations[ci].InterfaceTypes()[ii], name, signature);
                    if (inherited >= 0) { return inherited; }
                    ii = ii + 1;
                }
            }
            failure = "unsupported or undefined native method: " + owner + "." + name;
            return -1;
        }

        private int FindDeclaredFunction(string owner, string name, string signature) {
            int i = 0;
            while (i < functionCount) {
                if (functions[i].Owner() == owner && functions[i].Declaration().Name() == name &&
                    Signature(functions[i].Declaration()) == signature) { return i; }
                i = i + 1;
            }
            return -1;
        }

        private int DispatchTarget(string runtimeType, int fallback) {
            string current = runtimeType; string name = functions[fallback].Declaration().Name();
            string signature = Signature(functions[fallback].Declaration()); int depth = 0;
            while (current != "" && depth < 64) {
                int candidate = FindDeclaredFunction(current, name, signature);
                if (candidate >= 0) {
                    if (candidate == fallback || functions[candidate].Declaration().IsOverride()) { return candidate; }
                }
                int ci = ClassIndex(current); if (ci < 0) { break; }
                current = classDeclarations[ci].BaseType(); depth = depth + 1;
            }
            return fallback;
        }

        private int InterfaceDispatchTarget(string runtimeType, int fallback) {
            string current = runtimeType; string name = functions[fallback].Declaration().Name();
            string signature = Signature(functions[fallback].Declaration()); int depth = 0;
            while (current != "" && depth < 64) {
                int candidate = FindDeclaredFunction(current, name, signature);
                if (candidate >= 0) { return candidate; }
                int ci = ClassIndex(current); if (ci < 0) { break; }
                current = classDeclarations[ci].BaseType(); depth = depth + 1;
            }
            return -1;
        }

        private void EmitVirtualCall(int fallback, int argumentCount) {
            int[] endPatches = new int[0]; int endCount = 0; int ci = 0;
            int ownerIndex = ClassIndex(functions[fallback].Owner());
            bool interfaceCall = ownerIndex >= 0 && classDeclarations[ownerIndex].IsInterface();
            while (ci < classCount) {
                bool candidateType = classNames[ci] != functions[fallback].Owner() && DerivedFrom(classNames[ci], functions[fallback].Owner());
                if (interfaceCall) { candidateType = !classDeclarations[ci].IsInterface() && Implements(classNames[ci], functions[fallback].Owner(), 0); }
                if (candidateType) {
                    int target = DispatchTarget(classNames[ci], fallback);
                    if (interfaceCall) { target = InterfaceDispatchTarget(classNames[ci], fallback); }
                    if (target >= 0 && target != fallback) {
                        code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x84); code.EmitByte(0x24); code.Emit32(argumentCount * 8); // receiver
                        code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0x38); code.Emit32(ci + 1); // cmp [rax], type id
                        code.EmitByte(0x0f); code.EmitByte(0x85); int nextPatch = code.Position(); code.Emit32(0); // jne next
                        EmitCall(target);
                        int endPatch = EmitJump(); endPatches = AppendInt(endPatches, endCount, endPatch); endCount = endCount + 1;
                        PatchRelative(nextPatch, code.Position());
                    }
                }
                ci = ci + 1;
            }
            if (interfaceCall) { EmitRuntime("rt_null_error"); }
            else { EmitCall(fallback); }
            int i = 0; while (i < endCount) { PatchRelative(endPatches[i], code.Position()); i = i + 1; }
        }

        private bool CompileConstructorInitializer(string owner, IrMethod constructor) {
            int ci = ClassIndex(owner); if (ci < 0) { return true; }
            string kind = constructor.ConstructorInitializerKind();
            string targetOwner = owner;
            IrExpression[] arguments = constructor.ConstructorInitializerArguments();
            string signature = constructor.ConstructorInitializerSignature();
            if (kind == "") {
                if (classDeclarations[ci].BaseType() == "") { return true; }
                kind = "base"; targetOwner = classDeclarations[ci].BaseType(); arguments = new IrExpression[0];
                signature = SimpleName(targetOwner) + "()";
            } else if (kind == "base") { targetOwner = classDeclarations[ci].BaseType(); }
            if (signature == "") { signature = SimpleName(targetOwner) + "()"; }
            int target = FindFunction(targetOwner, SimpleName(targetOwner), signature);
            if (target < 0) { return false; }
            EmitLoadLocal(FindLocal("this")); code.EmitByte(0x50);
            IrParameter[] parameters = functions[target].Declaration().Parameters(); int i = 0;
            while (i < arguments.Length) {
                if (!CompileExpression(arguments[i])) { return false; }
                string expected = ResolveType(parameters[i].Type().DisplayName(), targetOwner);
                if (!Assignable(valueType, expected)) { failure = "native constructor initializer argument type mismatch"; return false; }
                PrepareValue(expected); code.EmitByte(0x50); i = i + 1;
            }
            EmitCall(target); DropSlots(arguments.Length + 1); return true;
        }

        private void EmitRuntime(string name) {
            code.EmitByte(0xe8);
            runtimeTargets = AppendString(runtimeTargets, runtimePatchCount, name);
            runtimePatches = AppendInt(runtimePatches, runtimePatchCount, code.Position());
            runtimePatchCount = runtimePatchCount + 1;
            code.Emit32(0);
        }

        private void MoveRdiRax() { code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc7); }
        private void DropSlots(int slots) {
            if (slots != 0) { code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xc4); code.Emit32(slots * 8); }
        }

        private void EmitLiteral(string text) {
            int index = AddPayload(text);
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x3d); // lea rdi, [rip+literal]
            AddPayloadPatch(code.Position(), index); code.Emit32(0);
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc6); code.Emit32(text.Length);
            EmitRuntime("rt_string");
        }

        private bool ConvertString(string type) {
            if (type == "string") { code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xf8); return true; }
            if (type == "bool") { EmitRuntime("rt_bool_string"); return true; }
            if (Numeric(type)) {
                if (Unsigned(type)) { EmitRuntime("rt_uint_string"); }
                else { EmitRuntime("rt_int_string"); }
                return true;
            }
            failure = "native string conversion requires a string, integral value, or bool"; return false;
        }

        private bool RuntimeCall(IrExpression expression, string runtime, string first, string second, string resultType) {
            IrExpression[] args = expression.Arguments();
            int count = 0;
            if (first != "") { count = 1; }
            if (second != "") { count = 2; }
            if (args.Length != count) { failure = "wrong argument count for native runtime intrinsic"; return false; }
            int i = 0;
            while (i < count) {
                if (!CompileExpression(args[i])) { return false; }
                string expected = first;
                if (i == 1) { expected = second; }
                if (!Assignable(valueType, expected)) { failure = "argument type mismatch for native runtime intrinsic"; return false; }
                NormalizeRax(expected);
                code.EmitByte(0x50); i = i + 1;
            }
            if (count == 2) { code.EmitByte(0x5e); }
            if (count >= 1) { code.EmitByte(0x5f); }
            EmitRuntime(runtime); valueType = resultType; return true;
        }

        private int ClassIndex(string name) {
            int i = 0;
            while (i < classCount) { if (classNames[i] == name) { return i; } i = i + 1; }
            return -1;
        }
        private int EnumIndex(string name) {
            int i = 0;
            while (i < enumCount) { if (enumNames[i] == name) { return i; } i = i + 1; }
            return -1;
        }
        private int FieldIndex(string owner, string name) {
            int ci = ClassIndex(owner);
            if (ci < 0) { return -1; }
            IrField[] fields = classDeclarations[ci].Fields();
            int i = 0;
            while (i < fields.Length) { if (fields[i].Name() == name) { return i; } i = i + 1; }
            return -1;
        }
        private string FieldOwner(string owner, string name) {
            int ci = ClassIndex(owner); if (ci < 0) { return ""; }
            if (FieldIndex(owner, name) >= 0) { return owner; }
            string baseType = classDeclarations[ci].BaseType();
            if (baseType != "") { return FieldOwner(baseType, name); }
            return "";
        }
        private int StaticFieldIndex(string owner, string name) {
            int i = 0; while (i < staticCount) { if (staticOwners[i] == owner && staticNames[i] == name) { return i; } i = i + 1; }
            return -1;
        }
        private int InstanceFieldCount(string owner) {
            int ci = ClassIndex(owner); if (ci < 0) { return 0; }
            int count = 0;
            if (classDeclarations[ci].BaseType() != "") { count = InstanceFieldCount(classDeclarations[ci].BaseType()); }
            IrField[] fields = classDeclarations[ci].Fields(); int i = 0;
            while (i < fields.Length) { if (!fields[i].IsStatic()) { count = count + 1; } i = i + 1; }
            return count;
        }
        private int InstanceFieldOffset(string owner, int fieldIndex) {
            int ci = ClassIndex(owner); int offset = 0;
            if (classDeclarations[ci].BaseType() != "") { offset = InstanceFieldCount(classDeclarations[ci].BaseType()); }
            IrField[] fields = classDeclarations[ci].Fields(); int i = 0;
            while (i < fieldIndex) { if (!fields[i].IsStatic()) { offset = offset + 1; } i = i + 1; }
            return offset;
        }
        private bool IsArray(string type) {
            if (type.Length < 2) { return false; }
            return type[type.Length - 2] == "[" && type[type.Length - 1] == "]";
        }
        private string ElementType(string type) {
            string result = "";
            int i = 0;
            while (i < type.Length - 2) { result = result + type[i]; i = i + 1; }
            return result;
        }
        private string SimpleName(string name) {
            string result = "";
            int i = 0;
            while (i < name.Length) { if (name[i] == ".") { result = ""; } else { result = result + name[i]; } i = i + 1; }
            return result;
        }
        private string ResolveType(string name, string owner) {
            return module.ResolveType(name, owner);
        }
        private bool PrimitiveNumeric(string type) {
            return type == "byte" || type == "sbyte" || type == "short" || type == "ushort" ||
                type == "int" || type == "uint" || type == "long" || type == "ulong" ||
                type == "nint" || type == "nuint";
        }
        private bool Numeric(string type) { return PrimitiveNumeric(type) || EnumIndex(type) >= 0; }
        private bool Unsigned(string type) {
            return type == "byte" || type == "ushort" || type == "uint" || type == "ulong" || type == "nuint";
        }
        private int NumericBits(string type) {
            if (type == "byte" || type == "sbyte") { return 8; }
            if (type == "short" || type == "ushort") { return 16; }
            if (type == "int" || type == "uint") { return 32; }
            if (Numeric(type)) { return 64; }
            return 0;
        }
        private bool UnsignedOperation(string left, string right) {
            int leftBits = NumericBits(left); int rightBits = NumericBits(right);
            bool leftUnsigned = Unsigned(left); bool rightUnsigned = Unsigned(right);
            if (leftBits < 32) { leftBits = 32; leftUnsigned = false; }
            if (rightBits < 32) { rightBits = 32; rightUnsigned = false; }
            if (leftBits > rightBits) { return leftUnsigned; }
            if (rightBits > leftBits) { return rightUnsigned; }
            return leftUnsigned || rightUnsigned;
        }
        private int TypeSize(string type) {
            int bits = NumericBits(type);
            if (bits != 0) { return bits / 8; }
            if (type == "bool") { return 1; }
            if (EnumIndex(type) >= 0) { return 8; }
            return StructSize(type, 0);
        }
        private int StructSize(string type, int depth) {
            if (depth > 32) { return -1; }
            int ci = ClassIndex(type);
            if (ci < 0 || !classDeclarations[ci].IsStruct()) { return -1; }
            IrField[] fields = classDeclarations[ci].Fields(); int total = 0; int i = 0;
            while (i < fields.Length) {
                if (!fields[i].IsStatic()) {
                    string fieldType = ResolveType(fields[i].Type().DisplayName(), type);
                    int size = NumericBits(fieldType);
                    if (size != 0) { size = size / 8; }
                    else if (fieldType == "bool") { size = 1; }
                    else if (EnumIndex(fieldType) >= 0) { size = 8; }
                    else { size = StructSize(fieldType, depth + 1); }
                    if (size < 0) { return -1; }
                    total = total + size;
                }
                i = i + 1;
            }
            return total;
        }
        private void NormalizeRax(string type) {
            if (type == "sbyte") { code.EmitByte(0x48); code.EmitByte(0x0f); code.EmitByte(0xbe); code.EmitByte(0xc0); }
            else if (type == "byte") { code.EmitByte(0x48); code.EmitByte(0x0f); code.EmitByte(0xb6); code.EmitByte(0xc0); }
            else if (type == "short") { code.EmitByte(0x48); code.EmitByte(0x0f); code.EmitByte(0xbf); code.EmitByte(0xc0); }
            else if (type == "ushort") { code.EmitByte(0x48); code.EmitByte(0x0f); code.EmitByte(0xb7); code.EmitByte(0xc0); }
            else if (type == "int") { code.EmitByte(0x48); code.EmitByte(0x63); code.EmitByte(0xc0); }
            else if (type == "uint") { code.EmitByte(0x89); code.EmitByte(0xc0); }
        }
        private void PrepareValue(string type) {
            NormalizeRax(type);
            int ci = ClassIndex(type);
            if (ci < 0 || !classDeclarations[ci].IsStruct()) { return; }
            int fields = InstanceFieldCount(type);
            code.EmitByte(0x50); // root the source while allocation can collect
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc7); code.Emit32(8 * (fields + 1));
            EmitRuntime("rt_alloc");
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0x00); code.Emit32(ci + 1); // object type id
            code.EmitByte(0x59); // rcx = relocated source
            int i = 0;
            while (i < fields) {
                code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x91); code.Emit32(8 * (i + 1)); // mov rdx,[rcx+field]
                code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x90); code.Emit32(8 * (i + 1)); // mov [rax+field],rdx
                i = i + 1;
            }
        }
        private bool Reference(string type) {
            int ci = ClassIndex(type);
            return type == "string" || IsArray(type) || (ci >= 0 && !classDeclarations[ci].IsStruct());
        }
        private bool SupportedType(string type, bool allowVoid) {
            if (allowVoid && type == "void") { return true; }
            if (IsArray(type)) { return SupportedType(ElementType(type), false); }
            return Numeric(type) || type == "bool" || type == "string" || ClassIndex(type) >= 0;
        }
        private bool Assignable(string actual, string expected) {
            return actual == expected || (PrimitiveNumeric(actual) && PrimitiveNumeric(expected)) ||
                (actual == "null" && Reference(expected)) || DerivedFrom(actual, expected) || Implements(actual, expected, 0);
        }
        private bool DerivedFrom(string actual, string expected) {
            string current = actual; int depth = 0;
            while (current != "" && depth < 64) {
                if (current == expected) { return true; }
                int ci = ClassIndex(current); if (ci < 0) { return false; }
                current = classDeclarations[ci].BaseType(); depth = depth + 1;
            }
            return false;
        }
        private bool Implements(string actual, string expected, int depth) {
            if (depth > 64) { return false; }
            int ci = ClassIndex(actual); if (ci < 0) { return false; }
            if (actual == expected && classDeclarations[ci].IsInterface()) { return true; }
            string[] interfaces = classDeclarations[ci].InterfaceTypes(); int i = 0;
            while (i < interfaces.Length) {
                if (interfaces[i] == expected || Implements(interfaces[i], expected, depth + 1)) { return true; }
                i = i + 1;
            }
            if (classDeclarations[ci].BaseType() != "") { return Implements(classDeclarations[ci].BaseType(), expected, depth + 1); }
            return false;
        }

        private bool CompileFieldAddress(IrExpression receiver, string name, string resolvedOwner) {
            string owner = functions[currentFunction].Owner();
            if (currentStaticOwner != "") { owner = currentStaticOwner; }
            if (resolvedOwner != "") { owner = resolvedOwner; }
            string declaredOwner = FieldOwner(owner, name);
            int declaredField = FieldIndex(declaredOwner, name);
            if (declaredField >= 0) {
                IrField possibleStatic = classDeclarations[ClassIndex(declaredOwner)].Fields()[declaredField];
                if (possibleStatic.IsStatic()) {
                    int staticIndex = StaticFieldIndex(declaredOwner, name);
                    if (staticIndex < 0) { failure = "undefined native static field: " + declaredOwner + "." + name; return false; }
                    code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xe8); // mov rax, r13
                    if (staticIndex > 0) { code.EmitByte(0x48); code.EmitByte(0x05); code.Emit32(staticIndex * 8); }
                    addressReadOnly = false; valueType = ResolveType(possibleStatic.Type().DisplayName(), declaredOwner); return true;
                }
            }
            if (receiver == null) {
                int slot = FindLocal("this");
                if (slot < 0) { failure = "instance field requires an object receiver"; return false; }
                EmitLoadLocal(slot);
            } else {
                if (!CompileExpression(receiver)) { return false; }
                owner = valueType;
            }
            MoveRdiRax(); EmitRuntime("rt_check");
            addressReadOnly = false;
            if (name == "Length" && (owner == "string" || IsArray(owner))) { addressReadOnly = true; valueType = "int"; return true; }
            declaredOwner = FieldOwner(owner, name);
            int field = FieldIndex(declaredOwner, name);
            if (field < 0) { failure = "undefined native field: " + owner + "." + name; return false; }
            IrField declaration = classDeclarations[ClassIndex(declaredOwner)].Fields()[field];
            if (declaration.IsStatic()) { failure = "static field requires a type receiver"; return false; }
            code.EmitByte(0x48); code.EmitByte(0x05); code.Emit32(8 * (InstanceFieldOffset(declaredOwner, field) + 1));
            valueType = ResolveType(declaration.Type().DisplayName(), declaredOwner);
            return true;
        }
        private void EmitFieldStore(int field) {
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x81); code.Emit32(8 * (field + 1));
        }
        private bool CompileAssignment(IrExpression expression) {
            IrExpression target = expression.Target();
            int slot = -1;
            string expected = "";
            if (target.Kind() == IrExpression.KindName()) { slot = FindLocal(target.Name()); }
            if (slot >= 0) { expected = localTypes[slot]; }
            else {
                if (target.Kind() == IrExpression.KindName()) {
                    if (!CompileFieldAddress(null, target.Name(), target.ResolvedOwner())) { return false; }
                } else if (target.Kind() == IrExpression.KindMemberAccess()) {
                    if (!CompileFieldAddress(target.Receiver(), target.MemberName(), target.ResolvedOwner())) { return false; }
                    if (addressReadOnly) { failure = "Length is read-only"; return false; }
                } else if (target.Kind() == IrExpression.KindIndex()) {
                    if (!CompileExpression(target.Receiver())) { return false; }
                    if (!IsArray(valueType)) { failure = "native indexed assignment requires array"; return false; }
                    expected = ElementType(valueType);
                    code.EmitByte(0x50);
                    if (!CompileExpression(target.Index())) { return false; }
                    if (!Numeric(valueType)) { failure = "native index must be integral"; return false; }
                    code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc6); code.EmitByte(0x5f);
                    EmitRuntime("rt_index"); valueType = expected;
                } else { failure = "unsupported native assignment target"; return false; }
                expected = valueType;
                code.EmitByte(0x50); // retain interior lvalue pointer as a GC root during RHS evaluation
            }
            if (!CompileExpression(expression.Value())) { return false; }
            if (!Assignable(valueType, expected)) { failure = "native assignment type mismatch"; return false; }
            PrepareValue(expected);
            if (slot >= 0) { EmitStoreLocal(slot); }
            else { code.EmitByte(0x59); code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x01); }
            valueType = expected; return true;
        }
        private bool CompileObject(IrExpression expression) {
            string owner = ResolveType(expression.Type().DisplayName(), functions[currentFunction].Owner());
            int ci = ClassIndex(owner);
            if (ci < 0) { failure = "unknown native class: " + owner; return false; }
            int constructor = FindFunction(owner, SimpleName(owner), expression.ResolvedSignature());
            if (constructor < 0) { return false; }
            IrParameter[] parameters = functions[constructor].Declaration().Parameters();
            IrExpression[] arguments = expression.Arguments();
            if (parameters.Length != arguments.Length) { failure = "wrong native constructor argument count"; return false; }
            int fields = InstanceFieldCount(owner);
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc7); code.Emit32(8 * (fields + 1));
            EmitRuntime("rt_alloc");
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0x00); code.Emit32(ci + 1); // object type id
            code.EmitByte(0x50);
            int i = 0;
            while (i < arguments.Length) {
                if (!CompileExpression(arguments[i])) { return false; }
                string parameterType = ResolveType(parameters[i].Type().DisplayName(), owner);
                if (!Assignable(valueType, parameterType)) { failure = "native constructor argument type mismatch"; return false; }
                PrepareValue(parameterType);
                code.EmitByte(0x50); i = i + 1;
            }
            EmitCall(constructor);
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x84); code.EmitByte(0x24); code.Emit32(8 * arguments.Length);
            DropSlots(arguments.Length + 1);
            valueType = owner; return true;
        }
        private bool CompileEnum(IrExpression expression) {
            string name = ResolveType(QualifiedName(expression.Receiver()), functions[currentFunction].Owner());
            int ei = EnumIndex(name);
            if (ei < 0) { return false; }
            IrEnumMember[] members = enumDeclarations[ei].Members();
            int i = 0;
            while (i < members.Length) {
                if (members[i].Name() == expression.MemberName()) { EmitMoveRaxImmediate(members[i].Value()); valueType = name; return true; }
                i = i + 1;
            }
            return false;
        }

        private string RootName(string name) {
            string result = "";
            int i = 0;
            while (i < name.Length) { if (name[i] == ".") { return result; } result = result + name[i]; i = i + 1; }
            return result;
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

        private string NamespaceOf(string owner) {
            int last = -1;
            int i = 0;
            while (i < owner.Length) { if (owner[i] == ".") { last = i; } i = i + 1; }
            string result = "";
            i = 0;
            while (i < last) { result = result + owner[i]; i = i + 1; }
            return result;
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

        private int AddLocal(string name, string type) {
            int i = scopeStart;
            while (i < localCount) {
                if (localNames[i] == name) { failure = "duplicate native local: " + name; return -1; }
                i = i + 1;
            }
            localNames = AppendString(localNames, localCount, name);
            localTypes = AppendString(localTypes, localCount, type);
            int result = localCount;
            localCount = localCount + 1;
            if (localCount > maxLocalCount) { maxLocalCount = localCount; }
            return result;
        }

        private int FindLocal(string name) {
            int i = localCount - 1;
            while (i >= 0) {
                if (localNames[i] == name) { return i; }
                i = i - 1;
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
