using Hydrogen.Compiler.IR;

namespace Hydrogen.Compiler.CodeGen.X64 {
    // The direct backend intentionally starts with an executable language subset.
    // It does not rely on C emission, an assembler, or a linker at runtime.
	public class DirectImageResult {
		private bool success;
		private byte[] image;
		private string message;
		private int panicEntryOffset;

		public DirectImageResult(bool inputSuccess, byte[] inputImage, string inputMessage, int inputPanicEntryOffset) {
			success = inputSuccess;
			image = inputImage;
			message = inputMessage;
			panicEntryOffset = inputPanicEntryOffset;
		}

		public bool Success() { return success; }
		public byte[] Image() { return image; }
		public string Message() { return message; }
		public int PanicEntryOffset() { return panicEntryOffset; }
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
        private Hydrogen.Compiler.Core.BuildProgress buildProgress;
        private int emittedMethods;

        public void SetBuildProgress(Hydrogen.Compiler.Core.BuildProgress value) {
            buildProgress = value;
        }

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
        // A packed array made with new T[n] keeps its immutable length equal
        // to n until either local is assigned again.
        private int[] arrayLengthSourceSlots;
        private int provenIndexSlot;
        private int provenArraySlot;
        private int provenBoundSlot;
        private bool provenNonNegative;
        private bool loopStartsAtZero;
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
        private bool freestanding;
        private bool windows;

        public DirectImageResult Compile(IrModule input) {
            return CompilePlatform(input, false);
        }

        public DirectImageResult CompileWindows(IrModule input) {
            return CompilePlatform(input, true);
        }

        private DirectImageResult CompilePlatform(IrModule input, bool forWindows) {
            Reset(input);
            freestanding = false;
            windows = forWindows;
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
            // The original stack is the upper bound for conservative GC roots.
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xe6); // mov r14, rsp
            if (windows) {
                code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xe4); code.EmitByte(0xf0); // align rsp for internal calls
            }
            EmitRuntime("rt_init"); // r15 owns heap state for the lifetime of the process
            if (staticCount > 0) {
                code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc7); code.Emit32(staticCount * 8);
                EmitRuntime("rt_alloc");
                code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xc5); // mov r13, rax: rooted static storage
            } else {
                code.EmitByte(0x45); code.EmitByte(0x31); code.EmitByte(0xed); // xor r13d, r13d
            }
            currentFunction = mainFunction;
            localNames = new string[0]; localTypes = new string[0]; arrayLengthSourceSlots = new int[0];
            localCount = 0; scopeStart = 0; loopStart = -1;
            provenIndexSlot = -1; provenArraySlot = -1; provenBoundSlot = -1;
            provenNonNegative = false; loopStartsAtZero = false;
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
            if (!CompileNeededFunctions()) { return Failed(failure); }
            int runtimeStart = code.Position();
            NativeRuntimeEmitter linuxRuntime = null;
            WindowsRuntimeEmitter windowsRuntime = null;
            if (windows) {
                windowsRuntime = new WindowsRuntimeEmitter();
                windowsRuntime.Emit(code);
            } else {
                linuxRuntime = new NativeRuntimeEmitter();
                linuxRuntime.Emit(code);
            }
            i = 0;
            while (i < runtimePatchCount) {
                int offset = -1;
                if (windows) { offset = windowsRuntime.Offset(runtimeTargets[i]); }
                else { offset = linuxRuntime.Offset(runtimeTargets[i]); }
                if (offset < 0) { return Failed("unknown native runtime helper: " + runtimeTargets[i]); }
                PatchRelative(runtimePatches[i], runtimeStart + offset);
                i = i + 1;
            }
            ElfImageBuilder imageBuilder = new ElfImageBuilder();
            if (windows) {
                WindowsImageBuilder windowsImage = new WindowsImageBuilder();
                byte[] executable = windowsImage.BuildCodeAndData(code.ToArray(), payloads,
                    payloadPatchOffsets, payloadPatchIndexes, runtimeStart, windowsRuntime);
                if (executable == null) { return Failed("Windows PE image exceeds format limits"); }
                return new DirectImageResult(true, executable, "", -1);
            }
            return new DirectImageResult(true, imageBuilder.BuildCodeAndData(code.ToArray(), payloads, payloadPatchOffsets, payloadPatchIndexes), "", -1);
        }

        // Emit only a reachable freestanding method graph. The EFI handoff
        // passes one boot-information pointer on the Hydrogen stack and checks
        // the returned int status. Runtime helpers use the kernel's page range.
		public DirectImageResult CompileFreestanding(IrModule input, string owner, string methodName) {
			return CompileFreestanding(input, owner, methodName, false);
		}

		public DirectImageResult CompileFreestanding(IrModule input, string owner, string methodName, bool includePanic) {

			Reset(input);
            freestanding = true;
            windows = false;
            mainFunction = -1;
            if (staticCount != 0) { return Failed("freestanding entry does not yet support static fields"); }
            int entry = -1;
            int i = 0;
            while (i < functionCount) {
                if (functions[i].Owner() == owner && functions[i].Declaration().Name() == methodName &&
                    functions[i].Declaration().IsStatic()) {
                    if (entry >= 0) { return Failed("ambiguous freestanding entry method"); }
                    entry = i;
                }
                i = i + 1;
            }
            if (entry < 0) { return Failed("missing freestanding entry method " + owner + "." + methodName); }
            IrMethod method = functions[entry].Declaration();
            if (method.ReturnType().DisplayName() != "int" || method.Parameters().Length != 1 ||
                method.Parameters()[0].Type().DisplayName() != "long") {
                return Failed("freestanding entry must be static int Run(long bootInfo)");
            }
			functions[entry].Require();

			int panicEntry = -1;

			// Include the kernel's additional panic entry point.
			if (includePanic) {
				i = 0;

				while (i < functionCount) {
					if (functions[i].Owner() == "Australis.Kernel.Diagnostics.PanicQr" && functions[i].Declaration().Name() == "Render" && functions[i].Declaration().IsStatic()) {
						if (panicEntry >= 0) { return Failed("ambiguous panic entry point"); }
						panicEntry = i;
					}
					i = i + 1;
				}
				if (panicEntry < 0) { return Failed("missing PanicQr.Render entry point"); }
				IrMethod panicMethod = functions[panicEntry].Declaration();
				if (panicMethod.ReturnType().DisplayName() != "int" ||
					panicMethod.Parameters().Length != 1 ||
					panicMethod.Parameters()[0].Type().DisplayName() != "long") {

					return Failed("panic entry must be static int Render(long bootInfo)");
				}

				functions[panicEntry].Require();
			}

			if (!CompileNeededFunctions()) { return Failed(failure); }
            if (functions[entry].Position() != 0) {
                return Failed("freestanding entry must start at code offset zero");
            }
            if (runtimePatchCount > 0) {
                FreestandingRuntimeEmitter runtime = new FreestandingRuntimeEmitter();
                int runtimeStart = code.Position();
                runtime.Emit(code);
                i = 0;
                while (i < runtimePatchCount) {
                    int offset = runtime.Offset(runtimeTargets[i]);
                    if (offset < 0) { return Failed("unsupported freestanding runtime helper: " + runtimeTargets[i]); }
                    PatchRelative(runtimePatches[i], runtimeStart + offset);
                    i = i + 1;
                }
            }
            ElfImageBuilder ascii = new ElfImageBuilder();
            int[] payloadOffsets = new int[payloadCount];
            i = 0;
            while (i < payloadCount) {
                if (!ascii.SupportsPayload(payloads[i])) { return Failed("non-ASCII freestanding literal"); }
                payloadOffsets[i] = code.Position();
                int ch = 0;
                while (ch < payloads[i].Length) {
                    code.EmitByte(ascii.AsciiCode(payloads[i][ch]));
                    ch = ch + 1;
                }
                i = i + 1;
            }
            i = 0;
            while (i < payloadPatchCount) {
                PatchRelative(payloadPatchOffsets[i], payloadOffsets[payloadPatchIndexes[i]]);
                i = i + 1;
            }

            int panicOffset = -1;

			if (includePanic) {
				panicOffset = functions[panicEntry].Position();

				if (panicOffset <= 0) {
					return Failed("panic entry was not emitted");
				}
			}

			return new DirectImageResult(true, code.ToArray(), "", panicOffset);
        }

        private bool CompileNeededFunctions() {
            bool progress = true;
            while (progress) {
                progress = false;
                int i = 0;
                while (i < functionCount) {
                    if (functions[i].Needed() && functions[i].Position() < 0) {
                        currentFunction = i;
                        if (!CompileFunction()) {
                            failure = functions[i].Owner() + "." + functions[i].Declaration().Name() + ": " + failure;
                            return false;
                        }
                        emittedMethods = emittedMethods + 1;
                        // A method's temporary lowering/codegen objects are
                        // no longer needed once its machine code is emitted.
                        // Bound retained memory during large self-builds.
                        if (emittedMethods % 16 == 0) { System.Runtime.GC.Collect(); }
                        if (buildProgress != null && emittedMethods % 10 == 0) {
                            buildProgress.Pulse("Compiled " + emittedMethods + " methods");
                        }
                        progress = true;
                    }
                    i = i + 1;
                }
            }
            int i = 0;
            while (i < callPatchCount) {
                PatchRelative(callPatchOffsets[i], functions[callPatchTargets[i]].Position());
                i = i + 1;
            }
            if (buildProgress != null) { buildProgress.Pulse("Compiled " + emittedMethods + " methods"); }
            return true;
        }

        private void Reset(IrModule input) {
            emittedMethods = 0;
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
        }

        private DirectImageResult Failed(string message) {
            return new DirectImageResult(false, new byte[0], message, -1);
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
            arrayLengthSourceSlots = new int[0];
            localCount = 0;
            maxLocalCount = 0;
            scopeStart = 0;
            loopStart = -1;
            provenIndexSlot = -1; provenArraySlot = -1; provenBoundSlot = -1;
            provenNonNegative = false; loopStartsAtZero = false;
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
                    bool previousZero = loopStartsAtZero;
                    loopStartsAtZero = false;
                    if (i > 0 && items[i].Kind() == IrStatement.KindWhileStatement()) {
                        IrExpression condition = items[i].Condition();
                        if (condition != null && condition.Kind() == IrExpression.KindBinary() &&
                            condition.Left().Kind() == IrExpression.KindName()) {
                            loopStartsAtZero = ZeroSetter(items[i - 1], condition.Left().Name());
                        }
                    }
                    if (!CompileStatement(items[i])) { return false; }
                    loopStartsAtZero = previousZero;
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
                IrExpression initializer = statement.Initializer();
                if ((type == "byte[]" || type == "int[]") && initializer != null &&
                    initializer.Kind() == IrExpression.KindArrayCreation() &&
                    initializer.Size().Kind() == IrExpression.KindName()) {
                    int lengthSlot = FindLocal(initializer.Size().Name());
                    if (lengthSlot >= 0 && localTypes[lengthSlot] == "int") {
                        arrayLengthSourceSlots[slot] = lengthSlot;
                    }
                }
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
                int elsePatch = CompileConditionJumpFalse(statement.Condition(), -1);
                if (elsePatch < 0) { return false; }
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
                int previousIndex = provenIndexSlot;
                int previousArray = provenArraySlot;
                int previousBound = provenBoundSlot;
                bool previousNonNegative = provenNonNegative;
                ActivateProvenLoop(statement.Condition(), statement.Body(), null, loopStartsAtZero);
                int checkedLengthSlot = ProvenLengthConditionSlot(statement.Condition());
                if (checkedLengthSlot >= 0) { EmitProvenLengthPrecheck(checkedLengthSlot); }
                int conditionPosition = code.Position();
                loopStart = conditionPosition;
                int exitPatch = CompileConditionJumpFalse(statement.Condition(), checkedLengthSlot);
                if (exitPatch < 0) { return false; }
                if (!CompileStatement(statement.Body())) { return false; }
                provenIndexSlot = previousIndex; provenArraySlot = previousArray; provenBoundSlot = previousBound;
                provenNonNegative = previousNonNegative;
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
                int previousIndex = provenIndexSlot;
                int previousArray = provenArraySlot;
                int previousBound = provenBoundSlot;
                bool previousNonNegative = provenNonNegative;
                bool forStartsZero = false;
                if (statement.Condition() != null && statement.Condition().Kind() == IrExpression.KindBinary() &&
                    statement.Condition().Left().Kind() == IrExpression.KindName()) {
                    forStartsZero = ZeroSetter(statement.ForInitializer(), statement.Condition().Left().Name());
                }
                ActivateProvenLoop(statement.Condition(), statement.Body(), statement.ForIncrement(), forStartsZero);
                int checkedLengthSlot = ProvenLengthConditionSlot(statement.Condition());
                if (checkedLengthSlot >= 0) { EmitProvenLengthPrecheck(checkedLengthSlot); }
                int conditionPosition = code.Position();
                loopStart = -2;
                int exitPatch = CompileConditionJumpFalse(statement.Condition(), checkedLengthSlot);
                if (exitPatch < 0) { return false; }
                if (!CompileStatement(statement.Body())) { return false; }
                provenIndexSlot = previousIndex; provenArraySlot = previousArray; provenBoundSlot = previousBound;
                provenNonNegative = previousNonNegative;

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

        // Only a strict less-than loop with a stable index and immutable
        // array length can establish an upper bound for indexed accesses.
        // The final increment is excluded from the guarded body. Negative
        // indexes remain checked at each access, including after int wrap.
        private void ActivateProvenLoop(IrExpression condition, IrStatement body, IrExpression forIncrement, bool startsZero) {
            provenIndexSlot = -1; provenArraySlot = -1; provenBoundSlot = -1;
            provenNonNegative = false;
            if (condition == null || condition.Kind() != IrExpression.KindBinary() ||
                condition.OperatorKind() != IrOperator.LessToken() ||
                condition.Left().Kind() != IrExpression.KindName() ||
                body == null || body.Kind() != IrStatement.KindBlock()) { return; }
            int indexSlot = FindLocal(condition.Left().Name());
            if (indexSlot < 0 || localTypes[indexSlot] != "int") { return; }
            IrExpression right = condition.Right();
            int arraySlot = -1;
            int boundSlot = -1;
            if (right.Kind() == IrExpression.KindMemberAccess() && !right.NullConditional() &&
                right.MemberName() == "Length" &&
                right.Receiver() != null && right.Receiver().Kind() == IrExpression.KindName()) {
                arraySlot = FindLocal(right.Receiver().Name());
                if (arraySlot < 0 || (localTypes[arraySlot] != "byte[]" && localTypes[arraySlot] != "int[]")) { return; }
            } else if (right.Kind() == IrExpression.KindName()) {
                boundSlot = FindLocal(right.Name());
                if (boundSlot < 0 || localTypes[boundSlot] != "int" || boundSlot == indexSlot) { return; }
            } else { return; }
            IrStatement[] items = body.Statements();
            int prefixCount = items.Length;
            if (forIncrement == null) {
                if (prefixCount == 0 || items[prefixCount - 1].Kind() != IrStatement.KindExpressionStatement() ||
                    !CanonicalIncrement(items[prefixCount - 1].Expression(), indexSlot)) { return; }
                prefixCount = prefixCount - 1;
            } else if (!CanonicalIncrement(forIncrement, indexSlot)) { return; }
            int i = 0;
            while (i < prefixCount) {
                if (items[i].Kind() != IrStatement.KindExpressionStatement() ||
                    !GuardedExpressionSafe(items[i].Expression(), indexSlot, arraySlot, boundSlot)) { return; }
                i = i + 1;
            }
            provenIndexSlot = indexSlot;
            provenArraySlot = arraySlot;
            provenBoundSlot = boundSlot;
            provenNonNegative = startsZero;
        }

        private bool ZeroSetter(IrStatement statement, string name) {
            if (statement == null) { return false; }
            IrExpression value = null;
            if (statement.Kind() == IrStatement.KindVariableDeclaration() && statement.Name() == name) {
                value = statement.Initializer();
            } else if (statement.Kind() == IrStatement.KindExpressionStatement()) {
                IrExpression expression = statement.Expression();
                if (expression != null && expression.Kind() == IrExpression.KindAssignment() &&
                    expression.AssignmentOperatorKind() == IrOperator.EqualsToken() &&
                    expression.Target().Kind() == IrExpression.KindName() && expression.Target().Name() == name) {
                    value = expression.Value();
                }
            }
            return value != null && value.Kind() == IrExpression.KindLiteral() &&
                value.LiteralKind() == "number" && value.LiteralText() == "0";
        }

        private bool CanonicalIncrement(IrExpression expression, int indexSlot) {
            if (expression == null || expression.Kind() != IrExpression.KindAssignment() ||
                expression.AssignmentOperatorKind() != IrOperator.EqualsToken() ||
                expression.Target().Kind() != IrExpression.KindName() ||
                FindLocal(expression.Target().Name()) != indexSlot) { return false; }
            IrExpression value = expression.Value();
            return value.Kind() == IrExpression.KindBinary() && value.OperatorKind() == IrOperator.PlusToken() &&
                value.Left().Kind() == IrExpression.KindName() && FindLocal(value.Left().Name()) == indexSlot &&
                value.Right().Kind() == IrExpression.KindLiteral() &&
                value.Right().LiteralKind() == "number" && value.Right().LiteralText() == "1";
        }

        private bool GuardedExpressionSafe(IrExpression expression, int indexSlot, int arraySlot, int boundSlot) {
            if (expression == null) { return true; }
            int kind = expression.Kind();
            if (kind == IrExpression.KindName() || kind == IrExpression.KindLiteral()) { return true; }
            if (kind == IrExpression.KindBinary()) {
                return GuardedExpressionSafe(expression.Left(), indexSlot, arraySlot, boundSlot) &&
                    GuardedExpressionSafe(expression.Right(), indexSlot, arraySlot, boundSlot);
            }
            if (kind == IrExpression.KindIndex()) {
                return GuardedExpressionSafe(expression.Receiver(), indexSlot, arraySlot, boundSlot) &&
                    GuardedExpressionSafe(expression.Index(), indexSlot, arraySlot, boundSlot);
            }
            if (kind == IrExpression.KindMemberAccess()) {
                return GuardedExpressionSafe(expression.Receiver(), indexSlot, arraySlot, boundSlot);
            }
            if (kind == IrExpression.KindCast()) {
                return GuardedExpressionSafe(expression.CastExpression(), indexSlot, arraySlot, boundSlot);
            }
            if (kind == IrExpression.KindAssignment()) {
                IrExpression target = expression.Target();
                if (target.Kind() == IrExpression.KindName()) {
                    int slot = FindLocal(target.Name());
                    if (slot == indexSlot || slot == arraySlot || slot == boundSlot ||
                        (slot >= 0 && (localTypes[slot] == "byte[]" || localTypes[slot] == "int[]"))) { return false; }
                } else if (target.Kind() != IrExpression.KindIndex()) { return false; }
                return GuardedExpressionSafe(target, indexSlot, arraySlot, boundSlot) &&
                    GuardedExpressionSafe(expression.Value(), indexSlot, arraySlot, boundSlot);
            }
            return false;
        }

        private bool ProvenPackedAccess(IrExpression receiver, IrExpression index) {
            if (provenIndexSlot < 0 || receiver.Kind() != IrExpression.KindName() ||
                index.Kind() != IrExpression.KindName() || FindLocal(index.Name()) != provenIndexSlot) { return false; }
            int arraySlot = FindLocal(receiver.Name());
            return arraySlot >= 0 && (arraySlot == provenArraySlot ||
                (provenBoundSlot >= 0 && arrayLengthSourceSlots[arraySlot] == provenBoundSlot));
        }

        private int ProvenLengthConditionSlot(IrExpression condition) {
            if (provenArraySlot < 0 || condition == null || condition.Kind() != IrExpression.KindBinary()) { return -1; }
            IrExpression right = condition.Right();
            if (right.Kind() != IrExpression.KindMemberAccess() || right.NullConditional() ||
                right.MemberName() != "Length" || right.Receiver().Kind() != IrExpression.KindName()) { return -1; }
            return FindLocal(right.Receiver().Name()) == provenArraySlot ? provenArraySlot : -1;
        }

        private void EmitProvenLengthPrecheck(int arraySlot) {
            EmitLoadLocal(arraySlot);
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xc0); // test rax, rax
            code.EmitByte(0x0f); code.EmitByte(0x85); int nonNull = code.Position(); code.Emit32(0);
            EmitRuntime("rt_null_error");
            PatchRelative(nonNull, code.Position());
        }

        // A branch can consume comparison flags directly. Materialising a
        // boolean with setcc/movzx and then testing it costs three extra
        // instructions in every loop iteration.
        private int CompileConditionJumpFalse(IrExpression condition, int checkedLengthSlot) {
            if (condition.Kind() == IrExpression.KindBinary() &&
                Numeric(condition.Left().ResultType()) && Numeric(condition.Right().ResultType())) {
                int op = condition.OperatorKind();
                if (op == IrOperator.LessToken() || op == IrOperator.LessEqualsToken() ||
                    op == IrOperator.GreaterToken() || op == IrOperator.GreaterEqualsToken()) {
                    if (!CompileExpression(condition.Left())) { return -1; }
                    string leftType = valueType;
                    IrExpression right = condition.Right();
                    int rightSlot = -1;
                    if (right.Kind() == IrExpression.KindName()) { rightSlot = FindLocal(right.Name()); }
                    if (checkedLengthSlot >= 0) {
                        code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc1); // mov rcx, rax
                        EmitLoadLocal(checkedLengthSlot);
                        code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x00); // mov rax, [rax]
                        valueType = "int";
                    } else if (rightSlot >= 0) {
                        code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc1); // mov rcx, rax
                        EmitLoadLocal(rightSlot);
                        valueType = localTypes[rightSlot];
                    } else {
                        code.EmitByte(0x50); // preserve left while evaluating right
                        if (!CompileExpression(right)) { return -1; }
                        code.EmitByte(0x59); // left in rcx, right in rax
                    }
                    string rightType = valueType;
                    if (!Numeric(leftType) || !Numeric(rightType) ||
                        (!Assignable(leftType, rightType) && !Assignable(rightType, leftType))) {
                        failure = "native binary operand type mismatch"; return -1;
                    }
                    code.EmitByte(0x48); code.EmitByte(0x39); code.EmitByte(0xc1); // cmp rcx, rax
                    bool unsignedComparison = UnsignedOperation(leftType, rightType);
                    code.EmitByte(0x0f);
                    if (op == IrOperator.LessToken()) { if (unsignedComparison) { code.EmitByte(0x83); } else { code.EmitByte(0x8d); } }
                    if (op == IrOperator.LessEqualsToken()) { if (unsignedComparison) { code.EmitByte(0x87); } else { code.EmitByte(0x8f); } }
                    if (op == IrOperator.GreaterToken()) { if (unsignedComparison) { code.EmitByte(0x86); } else { code.EmitByte(0x8e); } }
                    if (op == IrOperator.GreaterEqualsToken()) { if (unsignedComparison) { code.EmitByte(0x82); } else { code.EmitByte(0x8c); } }
                    int patch = code.Position(); code.Emit32(0);
                    valueType = "bool";
                    return patch;
                }
            }
            if (!CompileExpression(condition)) { return -1; }
            if (valueType != "bool") { failure = "native condition must be bool"; return -1; }
            return EmitJumpIfZero();
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
                int skip = -1;
                if (expression.NullConditional()) {
                    if (!CompileExpression(expression.Receiver())) { return false; }
                    if (!Reference(valueType) || !Reference(expression.ResultType())) {
                        failure = "native null-conditional field requires reference receiver and result"; return false;
                    }
                    skip = EmitJumpIfZero();
                }
                if (!CompileFieldAddressWithReceiver(expression.Receiver(), expression.MemberName(), expression.ResolvedOwner(), skip >= 0)) { return false; }
                code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x00);
                if (skip >= 0) { FinishOptional(skip); }
                return true;
            }
            if (kind == IrExpression.KindIndex()) {
                if (!CompileExpression(expression.Receiver())) { return false; }
                string receiverType = valueType;
                int skip = -1;
                if (expression.NullConditional()) {
                    if (!Reference(receiverType) || !Reference(expression.ResultType())) {
                        failure = "native null-conditional index requires reference receiver and result"; return false;
                    }
                    skip = EmitJumpIfZero();
                }
                // A proved packed-array read needs neither an element address
                // nor a temporary receiver register. Fold the element load
                // into the array/index addressing mode.
                if (!freestanding && (receiverType == "byte[]" || receiverType == "int[]") &&
                    ProvenPackedAccess(expression.Receiver(), expression.Index())) {
                    int provenSlot = FindLocal(expression.Index().Name());
                    EmitProvenPackedRead(provenSlot, receiverType == "byte[]" ? 1 : 4);
                    valueType = ElementType(receiverType);
                    if (skip >= 0) { FinishOptional(skip); }
                    return true;
                }
                if (!CompileIndexOperands(expression.Index())) { return false; }
                if (receiverType == "string") { EmitRuntime("rt_char"); valueType = "string"; }
                else if (!IsArray(receiverType)) { failure = "native indexing requires array or string"; return false; }
                else if (!freestanding && receiverType == "byte[]") {
                    if (ProvenPackedAccess(expression.Receiver(), expression.Index())) { EmitProvenPackedIndex(1); }
                    else { EmitCheckedPackedIndex(1); }
                    code.EmitByte(0x0f); code.EmitByte(0xb6); code.EmitByte(0x00); // movzx eax, byte [rax]
                } else if (!freestanding && receiverType == "int[]") {
                    if (ProvenPackedAccess(expression.Receiver(), expression.Index())) { EmitProvenPackedIndex(4); }
                    else { EmitCheckedPackedIndex(4); }
                    code.EmitByte(0x48); code.EmitByte(0x63); code.EmitByte(0x00); // movsxd rax, dword [rax]
                } else {
                    EmitRuntime("rt_index");
                    code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x00);
                }
                if (receiverType != "string") { valueType = ElementType(receiverType); }
                if (skip >= 0) { FinishOptional(skip); }
                return true;
            }
            if (kind == IrExpression.KindSlice()) {
                if (freestanding) { failure = "slicing is not supported for freestanding targets"; return false; }
                if (!CompileExpression(expression.Receiver())) { return false; }
                string receiverType = valueType;
                if (receiverType != "string" && !IsArray(receiverType)) {
                    failure = "native slicing requires an array or string"; return false;
                }
                code.EmitByte(0x50); // preserve receiver
                if (!CompileExpression(expression.Index())) { return false; }
                if (valueType != "int") { failure = "native slice start must be int"; return false; }
                code.EmitByte(0x50); // preserve start
                if (!CompileExpression(expression.SliceEnd())) { return false; }
                if (valueType != "int") { failure = "native slice end must be int"; return false; }
                code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc2); // mov rdx, rax
                code.EmitByte(0x5e); // pop rsi
                code.EmitByte(0x5f); // pop rdi
                int elementBytes = 8;
                if (receiverType == "string") { elementBytes = 0; }
                else if (receiverType == "byte[]") { elementBytes = 1; }
                else if (receiverType == "int[]") { elementBytes = 4; }
                code.EmitByte(0xb9); code.Emit32(elementBytes); // mov ecx, element width
                EmitRuntime("rt_slice");
                valueType = receiverType;
                return true;
            }
            if (kind == IrExpression.KindArrayCreation()) {
                string type = ResolveType(expression.Type().DisplayName(), functions[currentFunction].Owner());
                if (!SupportedType(type, false)) { failure = "unsupported native array element type"; return false; }
                if (!CompileExpression(expression.Size())) { return false; }
                if (!Numeric(valueType)) { failure = "native array size must be integral"; return false; }
                MoveRdiRax();
                if (!freestanding && type == "byte") { EmitRuntime("rt_byte_array"); }
                else if (!freestanding && type == "int") { EmitRuntime("rt_int_array"); }
                else { EmitRuntime("rt_array"); }
                valueType = type + "[]"; return true;
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
                if (expression.UnaryOperatorKind() == IrOperator.TildeToken()) {
                    if (!Numeric(valueType)) { failure = "native bitwise complement requires an integral operand"; return false; }
                    code.EmitByte(0x48); code.EmitByte(0xf7); code.EmitByte(0xd0); // not rax
                    NormalizeRax(valueType);
                    return true;
                }
                failure = "unsupported unary operator";
                return false;
            }
            if (kind == IrExpression.KindConditional()) {
                string expected = expression.ResultType();
                if (!CompileExpression(expression.ConditionalCondition())) { return false; }
                if (valueType != "bool") { failure = "native conditional expression requires bool"; return false; }
                int elsePatch = EmitJumpIfZero();
                if (!CompileExpression(expression.TrueValue())) { return false; }
                if (!Assignable(valueType, expected)) { failure = "native conditional branch type mismatch"; return false; }
                PrepareValue(expected);
                int endPatch = EmitJump();
                PatchRelative(elsePatch, code.Position());
                if (!CompileExpression(expression.FalseValue())) { return false; }
                if (!Assignable(valueType, expected)) { failure = "native conditional branch type mismatch"; return false; }
                PrepareValue(expected);
                PatchRelative(endPatch, code.Position());
                valueType = expected;
                return true;
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
            if (op == IrOperator.QuestionQuestionToken()) {
                string expected = expression.ResultType();
                if (!CompileExpression(expression.Left())) { return false; }
                if (valueType != "null" && !Reference(valueType)) {
                    failure = "native null coalescing requires a reference operand"; return false;
                }
                if (!Assignable(valueType, expected)) { failure = "native null coalescing left type mismatch"; return false; }
                int rightPatch = EmitJumpIfZero();
                PrepareValue(expected);
                int endPatch = EmitJump();
                PatchRelative(rightPatch, code.Position());
                if (!CompileExpression(expression.Right())) { return false; }
                if (!Assignable(valueType, expected)) { failure = "native null coalescing fallback type mismatch"; return false; }
                PrepareValue(expected);
                PatchRelative(endPatch, code.Position());
                valueType = expected;
                return true;
            }
            if (op == IrOperator.AmpersandAmpersandToken() || op == IrOperator.PipePipeToken()) {
                return CompileLogical(expression);
            }
            if (!CompileExpression(expression.Left())) { return false; }
            string leftType = valueType;
            if (TryCompileImmediateBinary(expression, leftType)) { return true; }
            IrExpression right = expression.Right();
            int rightSlot = -1;
            if (right.Kind() == IrExpression.KindName()) { rightSlot = FindLocal(right.Name()); }
            if (rightSlot >= 0) {
                // Commutative integer operators can read the right local
                // directly into rcx, leaving the left value in rax.
                bool commutativeInteger =
                    (op == IrOperator.PlusToken() && leftType != "string" && localTypes[rightSlot] != "string") ||
                    op == IrOperator.StarToken() || op == IrOperator.AmpersandToken() ||
                    op == IrOperator.PipeToken() || op == IrOperator.CaretToken();
                if (commutativeInteger) { EmitLoadLocalRcx(rightSlot); }
                else {
                    // A local read cannot call into the runtime, so keep the
                    // left value in rcx without a push/pop.
                    code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc1); // mov rcx, rax
                    EmitLoadLocal(rightSlot);
                }
                valueType = localTypes[rightSlot];
            } else {
                code.EmitByte(0x50); // push rax
                if (!CompileExpression(right)) { return false; }
                code.EmitByte(0x59); // pop rcx (left), rax is right
            }
            string rightType = valueType;
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
                // Comparing with a one-byte literal is common in text scans.
                // Keep the null and length checks, but avoid a runtime call
                // and a general byte sequence comparison for this case.
                bool leftByteLiteral = expression.Left().Kind() == IrExpression.KindLiteral() &&
                    expression.Left().LiteralKind() == "string" && expression.Left().LiteralText().Length == 1;
                bool rightByteLiteral = expression.Right().Kind() == IrExpression.KindLiteral() &&
                    expression.Right().LiteralKind() == "string" && expression.Right().LiteralText().Length == 1;
                if (!freestanding && (leftByteLiteral || rightByteLiteral)) {
                    if (leftByteLiteral) { code.EmitByte(0x48); code.EmitByte(0x91); } // dynamic string in rcx
                    code.EmitByte(0x31); code.EmitByte(0xd2); // xor edx, edx
                    code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xc9); // test rcx, rcx
                    code.EmitByte(0x0f); code.EmitByte(0x84); int nullPatch = code.Position(); code.Emit32(0);
                    code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0x39); code.EmitByte(1); // cmp qword [rcx], 1
                    code.EmitByte(0x0f); code.EmitByte(0x85); int lengthPatch = code.Position(); code.Emit32(0);
                    code.EmitByte(0x8a); code.EmitByte(0x50); code.EmitByte(8); // mov dl, [rax+8]
                    code.EmitByte(0x38); code.EmitByte(0x51); code.EmitByte(8); // cmp [rcx+8], dl
                    code.EmitByte(0x0f); code.EmitByte(0x94); code.EmitByte(0xc2); // sete dl
                    PatchRelative(nullPatch, code.Position());
                    PatchRelative(lengthPatch, code.Position());
                    code.EmitByte(0x0f); code.EmitByte(0xb6); code.EmitByte(0xc2); // movzx eax, dl
                    if (op == IrOperator.BangEqualsToken()) { code.EmitByte(0x83); code.EmitByte(0xf0); code.EmitByte(1); }
                    valueType = "bool"; return true;
                }
                code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xcf);
                code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc6);
                EmitRuntime("rt_equal");
                if (op == IrOperator.BangEqualsToken()) { code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xf0); code.EmitByte(1); }
                valueType = "bool"; return true;
            }
            if (op != IrOperator.ShiftLeftToken() && op != IrOperator.ShiftRightToken() &&
                !Assignable(leftType, rightType) && !Assignable(rightType, leftType)) {
                failure = "native binary operand type mismatch"; return false;
            }
            if ((op == IrOperator.AmpersandToken() || op == IrOperator.PipeToken() || op == IrOperator.CaretToken()) &&
                (leftType != rightType || !Numeric(leftType))) {
                failure = "native bitwise operators require matching integral operands"; return false;
            }
            if ((op == IrOperator.ShiftLeftToken() || op == IrOperator.ShiftRightToken()) &&
                (!PrimitiveNumeric(leftType) || !PrimitiveNumeric(rightType))) {
                failure = "native shift operators require integral operands"; return false;
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
                code.EmitByte(0x48); code.EmitByte(0x0f); code.EmitByte(0xaf); code.EmitByte(0xc1); // imul rax, rcx
                NormalizeRax(resultType); valueType = resultType;
                return true;
            }
            if (op == IrOperator.AmpersandToken() || op == IrOperator.PipeToken() || op == IrOperator.CaretToken()) {
                code.EmitByte(0x48);
                if (op == IrOperator.AmpersandToken()) { code.EmitByte(0x21); }
                if (op == IrOperator.PipeToken()) { code.EmitByte(0x09); }
                if (op == IrOperator.CaretToken()) { code.EmitByte(0x31); }
                code.EmitByte(0xc8); // operation rax, rcx
                NormalizeRax(resultType); valueType = resultType;
                return true;
            }
            if (op == IrOperator.ShiftLeftToken() || op == IrOperator.ShiftRightToken()) {
                code.EmitByte(0x48); code.EmitByte(0x91); // xchg rax, rcx: value in rax, count in rcx
                code.EmitByte(0x83); code.EmitByte(0xe1); code.EmitByte(NumericBits(resultType) - 1); // mask count
                code.EmitByte(0x48); code.EmitByte(0xd3);
                if (op == IrOperator.ShiftLeftToken()) { code.EmitByte(0xe0); } // shl rax, cl
                else if (Unsigned(leftType)) { code.EmitByte(0xe8); } // shr rax, cl
                else { code.EmitByte(0xf8); } // sar rax, cl
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

        // Keep the left operand in rax when the right operand is a numeric
        // literal. x64 encodes a signed 32-bit immediate directly, removing
        // the push/pop and literal load from common loop arithmetic.
        private bool TryCompileImmediateBinary(IrExpression expression, string leftType) {
            IrExpression right = expression.Right();
            if (right.Kind() != IrExpression.KindLiteral() || right.LiteralKind() != "number" ||
                !Numeric(leftType) || (!Assignable(leftType, "int") && !Assignable("int", leftType))) {
                return false;
            }
            int immediate = ParseInt(right.LiteralText());
            int op = expression.OperatorKind();
            string resultType = expression.ResultType();
            if (resultType == "") { resultType = leftType; }
            if ((op == IrOperator.SlashToken() || op == IrOperator.PercentToken()) &&
                leftType == "int" && resultType == "int" && immediate >= 3) {
                code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc1); // mov rcx, rax
                EmitIntConstantDivision(immediate, op == IrOperator.PercentToken());
                valueType = "int"; return true;
            }
            if (op == IrOperator.PlusToken()) {
                code.EmitByte(0x48); code.EmitByte(0x05); code.Emit32(immediate); // add rax, imm32
                NormalizeRax(resultType); valueType = resultType; return true;
            }
            if (op == IrOperator.MinusToken()) {
                code.EmitByte(0x48); code.EmitByte(0x2d); code.Emit32(immediate); // sub rax, imm32
                NormalizeRax(resultType); valueType = resultType; return true;
            }
            if (op == IrOperator.StarToken()) {
                code.EmitByte(0x48); code.EmitByte(0x69); code.EmitByte(0xc0); code.Emit32(immediate); // imul rax, rax, imm32
                NormalizeRax(resultType); valueType = resultType; return true;
            }
            if (op == IrOperator.EqualsEqualsToken() || op == IrOperator.BangEqualsToken() ||
                op == IrOperator.LessToken() || op == IrOperator.LessEqualsToken() ||
                op == IrOperator.GreaterToken() || op == IrOperator.GreaterEqualsToken()) {
                code.EmitByte(0x48); code.EmitByte(0x3d); code.Emit32(immediate); // cmp rax, imm32
                code.EmitByte(0x0f);
                if (op == IrOperator.EqualsEqualsToken()) { code.EmitByte(0x94); }
                if (op == IrOperator.BangEqualsToken()) { code.EmitByte(0x95); }
                if (op == IrOperator.LessToken()) { if (UnsignedOperation(leftType, "int")) { code.EmitByte(0x92); } else { code.EmitByte(0x9c); } }
                if (op == IrOperator.LessEqualsToken()) { if (UnsignedOperation(leftType, "int")) { code.EmitByte(0x96); } else { code.EmitByte(0x9e); } }
                if (op == IrOperator.GreaterToken()) { if (UnsignedOperation(leftType, "int")) { code.EmitByte(0x97); } else { code.EmitByte(0x9f); } }
                if (op == IrOperator.GreaterEqualsToken()) { if (UnsignedOperation(leftType, "int")) { code.EmitByte(0x93); } else { code.EmitByte(0x9d); } }
                code.EmitByte(0xc0); // setcc al
                code.EmitByte(0x48); code.EmitByte(0x0f); code.EmitByte(0xb6); code.EmitByte(0xc0);
                valueType = "bool"; return true;
            }
            return false;
        }

        // For |x| <= 2^31 and 3 <= divisor <= 2^31-1, the high half of
        // |x| * ceil(2^64/divisor) is exactly floor(|x|/divisor). Most
        // array and byte loop values are nonnegative: keep their path free
        // of the absolute-value and quotient sign-restoration instructions.
        // Negating the sign-extended dividend is safe even for int.MinValue.
        private void EmitIntConstantDivision(int divisor, bool remainder) {
            ulong magic = ((ulong)(-1) / (ulong)divisor) + (ulong)1;
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xc9); // test rcx, rcx
            code.EmitByte(0x0f); code.EmitByte(0x88); int negativePatch = code.Position(); code.Emit32(0); // js negative
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc8); // mov rax, rcx
            code.EmitByte(0x49); code.EmitByte(0xb9); code.Emit64((long)magic); // mov r9, reciprocal
            code.EmitByte(0x49); code.EmitByte(0xf7); code.EmitByte(0xe1); // mul r9; quotient in rdx
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xd0); // mov rax, rdx
            if (remainder) {
                code.EmitByte(0x48); code.EmitByte(0x69); code.EmitByte(0xc0); code.Emit32(divisor); // quotient * divisor
                code.EmitByte(0x48); code.EmitByte(0x29); code.EmitByte(0xc1); // sub rcx, rax
                code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc8); // mov rax, rcx
            }
            code.EmitByte(0xe9); int donePatch = code.Position(); code.Emit32(0);
            PatchRelative(negativePatch, code.Position());
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc8); // mov rax, rcx
            code.EmitByte(0x48); code.EmitByte(0xf7); code.EmitByte(0xd8); // neg rax
            code.EmitByte(0x49); code.EmitByte(0xb9); code.Emit64((long)magic);
            code.EmitByte(0x49); code.EmitByte(0xf7); code.EmitByte(0xe1); // mul r9
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xd0); // mov rax, rdx
            if (remainder) {
                code.EmitByte(0x48); code.EmitByte(0x69); code.EmitByte(0xc0); code.Emit32(divisor);
                code.EmitByte(0x48); code.EmitByte(0x01); code.EmitByte(0xc8); // negative dividend + quotient * divisor
            } else {
                code.EmitByte(0x48); code.EmitByte(0xf7); code.EmitByte(0xd8); // neg quotient
            }
            PatchRelative(donePatch, code.Position());
            NormalizeRax("int");
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
            if (intrinsic == "System.Kernel.Managed.Release") {
                if (!freestanding || arguments.Length != 1 || !CompileExpression(arguments[0]) ||
                    !Reference(valueType)) { failure = "invalid managed release"; return false; }
                MoveRdiRax(); EmitRuntime("rt_release"); valueType = "bool"; return true;
            }
            if (intrinsic == "System.Kernel.Memory.Read8" || intrinsic == "System.Kernel.Memory.Read16" ||
                intrinsic == "System.Kernel.Memory.Read32" || intrinsic == "System.Kernel.Memory.Read64") {
                if (!freestanding || arguments.Length != 1 || !CompileExpression(arguments[0]) ||
                    !Assignable(valueType, "long")) { failure = "invalid freestanding memory read"; return false; }
                if (intrinsic == "System.Kernel.Memory.Read8") {
                    code.EmitByte(0x0f); code.EmitByte(0xb6); code.EmitByte(0x00);
                } else if (intrinsic == "System.Kernel.Memory.Read16") {
                    code.EmitByte(0x0f); code.EmitByte(0xb7); code.EmitByte(0x00);
                } else if (intrinsic == "System.Kernel.Memory.Read32") {
                    code.EmitByte(0x8b); code.EmitByte(0x00);
                } else {
                    code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x00);
                }
                valueType = "long"; return true;
            }
            if (intrinsic == "System.Kernel.Memory.NoExecute") {
                if (!freestanding || arguments.Length != 0) { failure = "invalid freestanding NX mask"; return false; }
                // x86-64 page-table bit 63. A dedicated intrinsic avoids
                // narrowing this architectural 64-bit constant through the
                // language's ordinary numeric-literal path.
                code.EmitByte(0x48); code.EmitByte(0xb8);
                code.EmitByte(0); code.EmitByte(0); code.EmitByte(0); code.EmitByte(0);
                code.EmitByte(0); code.EmitByte(0); code.EmitByte(0); code.EmitByte(128);
                valueType = "long"; return true;
            }
            if (intrinsic == "System.Kernel.Memory.Write8" || intrinsic == "System.Kernel.Memory.Write16" ||
                intrinsic == "System.Kernel.Memory.Write32" || intrinsic == "System.Kernel.Memory.Write64") {
                if (!freestanding || arguments.Length != 2 || !CompileExpression(arguments[0]) ||
                    !Assignable(valueType, "long")) { failure = "invalid freestanding memory write address"; return false; }
                code.EmitByte(0x50); // preserve address while lowering value
                if (!CompileExpression(arguments[1]) || !Assignable(valueType, "long")) {
                    failure = "invalid freestanding memory write value"; return false;
                }
                code.EmitByte(0x59); // pop rcx
                if (intrinsic == "System.Kernel.Memory.Write8") {
                    code.EmitByte(0x88); code.EmitByte(0x01);
                } else if (intrinsic == "System.Kernel.Memory.Write16") {
                    code.EmitByte(0x66); code.EmitByte(0x89); code.EmitByte(0x01);
                } else if (intrinsic == "System.Kernel.Memory.Write32") {
                    code.EmitByte(0x89); code.EmitByte(0x01);
                } else {
                    code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x01);
                }
                valueType = "void"; return true;
            }
            if (intrinsic == "System.Kernel.Memory.Fence") {
                if (!freestanding || arguments.Length != 0) { failure = "invalid freestanding memory fence"; return false; }
                code.EmitByte(0x0f); code.EmitByte(0xae); code.EmitByte(0xf0); // mfence
                valueType = "void"; return true;
            }
            if (intrinsic == "System.Kernel.Cpu.Pause" || intrinsic == "System.Kernel.Cpu.Halt" ||
                intrinsic == "System.Kernel.Cpu.EnableInterrupts" ||
                intrinsic == "System.Kernel.Cpu.DisableInterrupts") {
                if (!freestanding || arguments.Length != 0) { failure = "invalid freestanding CPU operation"; return false; }
                if (intrinsic == "System.Kernel.Cpu.Pause") { code.EmitByte(0xf3); code.EmitByte(0x90); }
                else if (intrinsic == "System.Kernel.Cpu.Halt") { code.EmitByte(0xf4); }
                else if (intrinsic == "System.Kernel.Cpu.EnableInterrupts") { code.EmitByte(0xfb); }
                else { code.EmitByte(0xfa); }
                valueType = "void"; return true;
            }
            if (intrinsic == "System.Kernel.Cpu.ReadStackPointer" ||
                intrinsic == "System.Kernel.Cpu.ReadBasePointer" ||
                intrinsic == "System.Kernel.Cpu.ReadFlags" ||
                intrinsic == "System.Kernel.Cpu.ReadCr3" ||
                intrinsic == "System.Kernel.Cpu.ReadInstructionPointer") {
                if (!freestanding || arguments.Length != 0) { failure = "invalid freestanding register read"; return false; }
                if (intrinsic == "System.Kernel.Cpu.ReadStackPointer") {
                    code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xe0); // mov rax, rsp
                } else if (intrinsic == "System.Kernel.Cpu.ReadBasePointer") {
                    code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xe8); // mov rax, rbp
                } else if (intrinsic == "System.Kernel.Cpu.ReadFlags") {
                    code.EmitByte(0x9c); code.EmitByte(0x58); // pushfq; pop rax
                } else if (intrinsic == "System.Kernel.Cpu.ReadCr3") {
                    code.EmitByte(0x0f); code.EmitByte(0x20); code.EmitByte(0xd8); // mov rax, cr3
                } else {
                    code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x05); code.Emit32(0); // lea rax, [rip]
                }
                valueType = "long"; return true;
            }
            if (intrinsic == "System.Kernel.Cpu.InvalidatePage") {
                if (!freestanding || arguments.Length != 1 || !CompileExpression(arguments[0]) ||
                    !Assignable(valueType, "long")) { failure = "invalid freestanding page invalidation"; return false; }
                // invlpg [rax] invalidates precisely this virtual page in the
                // current address space without relying on firmware services.
                code.EmitByte(0x0f); code.EmitByte(0x01); code.EmitByte(0x38);
                valueType = "void"; return true;
            }
            if (intrinsic == "System.Kernel.Cpu.CallKernel") {
                if (!freestanding || arguments.Length != 2 ||
                    !CompileExpression(arguments[0]) || !Assignable(valueType, "long")) {
                    failure = "invalid freestanding kernel function address"; return false;
                }
                code.EmitByte(0x50); // preserve function address
                if (!CompileExpression(arguments[1]) || !Assignable(valueType, "long")) {
                    failure = "invalid freestanding kernel function argument"; return false;
                }
                code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc7); // rdi = argument
                code.EmitByte(0x41); code.EmitByte(0x5b); // pop r11 = function address
                code.EmitByte(0x41); code.EmitByte(0xff); code.EmitByte(0xd3); // call r11
                valueType = "long"; return true;
            }
            if (intrinsic == "System.Kernel.Cpu.Timestamp") {
                if (!freestanding || arguments.Length != 0) { failure = "invalid freestanding timestamp"; return false; }
                code.EmitByte(0x0f); code.EmitByte(0x31); // rdtsc -> edx:eax
                code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe2); code.EmitByte(32);
                code.EmitByte(0x48); code.EmitByte(0x09); code.EmitByte(0xd0);
                valueType = "long"; return true;
            }
            if (intrinsic == "System.Kernel.Port.Read8") {
                if (!freestanding || arguments.Length != 1 || !CompileExpression(arguments[0]) ||
                    !Assignable(valueType, "int")) { failure = "invalid freestanding port read"; return false; }
                code.EmitByte(0x66); code.EmitByte(0x89); code.EmitByte(0xc2); // mov dx, ax
                code.EmitByte(0x31); code.EmitByte(0xc0); // zero upper result bits
                code.EmitByte(0xec); // in al, dx
                valueType = "int"; return true;
            }
            if (intrinsic == "System.Kernel.Port.Write8") {
                if (!freestanding || arguments.Length != 2 || !CompileExpression(arguments[0]) ||
                    !Assignable(valueType, "int")) { failure = "invalid freestanding port write address"; return false; }
                code.EmitByte(0x50); // preserve port
                if (!CompileExpression(arguments[1]) || !Assignable(valueType, "int")) {
                    failure = "invalid freestanding port write value"; return false;
                }
                code.EmitByte(0x59); // rcx = port
                code.EmitByte(0x66); code.EmitByte(0x89); code.EmitByte(0xca); // mov dx, cx
                code.EmitByte(0xee); // out dx, al
                valueType = "void"; return true;
            }
            if (intrinsic == "System.Kernel.Port.Read32") {
                if (!freestanding || arguments.Length != 1 || !CompileExpression(arguments[0]) ||
                    !Assignable(valueType, "int")) { failure = "invalid freestanding dword port read"; return false; }
                code.EmitByte(0x66); code.EmitByte(0x89); code.EmitByte(0xc2); // mov dx, ax
                code.EmitByte(0xed); // in eax, dx
                valueType = "long"; return true;
            }
            if (intrinsic == "System.Kernel.Port.Write32") {
                if (!freestanding || arguments.Length != 2 || !CompileExpression(arguments[0]) ||
                    !Assignable(valueType, "int")) { failure = "invalid freestanding dword port write address"; return false; }
                code.EmitByte(0x50);
                if (!CompileExpression(arguments[1]) || !Assignable(valueType, "long")) {
                    failure = "invalid freestanding dword port write value"; return false;
                }
                code.EmitByte(0x59); code.EmitByte(0x66); code.EmitByte(0x89); code.EmitByte(0xca);
                code.EmitByte(0xef); // out dx, eax
                valueType = "void"; return true;
            }
            if (intrinsic == "System.Kernel.String.ByteAt") {
                if (!freestanding) { failure = "kernel string bytes require freestanding emission"; return false; }
                return RuntimeCall(expression, "rt_byte_at", "string", "int", "int");
            }
            if (intrinsic == "System.Kernel.String.FromBytes") {
                if (!freestanding) { failure = "kernel string conversion requires freestanding emission"; return false; }
                return RuntimeCall(expression, "rt_from_bytes", "byte[]", "int", "string");
            }
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
            if (intrinsic == "System.Console.WriteBytes") {
                return RuntimeCall(expression, "rt_console_bytes", "byte[]", "", "void");
            }
            if (intrinsic == "System.Console.IsTerminal") {
                return RuntimeCall(expression, "rt_isatty", "", "", "bool");
            }
            if (intrinsic == "System.Console.TerminalWidth") {
                return RuntimeCall(expression, "rt_terminal_width", "", "", "int");
            }
            if (intrinsic == "System.Console.Utf8ByteAt") {
                return RuntimeCall(expression, "rt_string_byte_at", "string", "int", "int");
            }
            if (intrinsic == "System.Text.Buffer.FromBytes") {
                return RuntimeCall(expression, "rt_string_from_bytes", "byte[]", "int", "string");
            }
            if (intrinsic == "System.IO.File.Exists") { return RuntimeCall(expression, "rt_exists", "string", "", "bool"); }
            if (intrinsic == "System.IO.File.ReadAllText") { return RuntimeCall(expression, "rt_read_text", "string", "", "string"); }
            if (intrinsic == "System.IO.File.ReadAllBytes") { return RuntimeCall(expression, "rt_read_bytes", "string", "", "byte[]"); }
            if (intrinsic == "System.IO.File.WriteAllText") { return RuntimeCall(expression, "rt_write_text", "string", "string", "void"); }
            if (intrinsic == "System.IO.File.WriteAllBytes") { return RuntimeCall(expression, "rt_write_bytes", "string", "byte[]", "void"); }
            if (intrinsic == "System.Host.Process.Run") { return RuntimeCall(expression, "rt_process_run", "string", "", "int"); }
            if (intrinsic == "System.Host.Process.IsWindows") { return RuntimeCall(expression, "rt_is_windows", "", "", "bool"); }
            if (intrinsic == "System.Convert.ToInt32") { return RuntimeCall(expression, "rt_to_int", "string", "", "int"); }
            if (intrinsic == "System.Runtime.GC.Collect") { return RuntimeCall(expression, "rt_gc", "", "", "void"); }
            if (intrinsic == "System.Runtime.GC.GetAllocatedBytes") { return RuntimeCall(expression, "rt_heapbytes", "", "", "int"); }
            if (RootName(intrinsic) == "System") {
                failure = "unsupported native runtime intrinsic: " + intrinsic; return false;
            }
            int optionalPatch = -1;
            if (expression.Target().Kind() == IrExpression.KindMemberAccess() && expression.Target().NullConditional()) {
                if (!CompileExpression(expression.Target().Receiver())) { return false; }
                if (!Reference(valueType) || !Reference(expression.ResultType())) {
                    failure = "native null-conditional call requires reference receiver and result"; return false;
                }
                optionalPatch = EmitJumpIfZero();
            }
            int target = ResolveFunction(expression, optionalPatch >= 0);
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
            if (optionalPatch >= 0) { FinishOptional(optionalPatch); }
            return true;
        }

        private int ResolveFunction(IrExpression call, bool receiverAlreadyLoaded) {
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
                    if (!receiverAlreadyLoaded && !CompileExpression(receiver)) { return -1; }
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

        // The receiver is in rax. A local index needs no expression call, so
        // load it directly into rsi and avoid spilling the receiver to stack.
        private bool CompileIndexOperands(IrExpression index) {
            int indexSlot = -1;
            if (index.Kind() == IrExpression.KindName()) { indexSlot = FindLocal(index.Name()); }
            if (indexSlot >= 0) {
                if (!Numeric(localTypes[indexSlot])) { failure = "native index must be integral"; return false; }
                code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0xb5);
                code.Emit32(-8 * (indexSlot + 1)); // mov rsi, [rbp-offset]
                MoveRdiRax();
                return true;
            }
            code.EmitByte(0x50);
            if (!CompileExpression(index)) { return false; }
            if (!Numeric(valueType)) { failure = "native index must be integral"; return false; }
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc6); // mov rsi, rax
            code.EmitByte(0x5f); // pop rdi
            return true;
        }

        // rdi is the array and rsi is the signed index. The unsigned length
        // comparison rejects negative indexes as well as indexes past the end.
        private void EmitCheckedPackedIndex(int elementBytes) {
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xff); // test rdi, rdi
            code.EmitByte(0x0f); code.EmitByte(0x85); int nonNull = code.Position(); code.Emit32(0);
            EmitRuntime("rt_null_error");
            PatchRelative(nonNull, code.Position());
            code.EmitByte(0x48); code.EmitByte(0x3b); code.EmitByte(0x37); // cmp rsi, [rdi]
            code.EmitByte(0x0f); code.EmitByte(0x82); int inRange = code.Position(); code.Emit32(0);
            EmitRuntime("rt_index_error");
            PatchRelative(inRange, code.Position());
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x44);
            if (elementBytes == 1) { code.EmitByte(0x37); }
            else { code.EmitByte(0xb7); }
            code.EmitByte(8); // lea rax, [rdi + rsi * elementBytes + 8]
        }

        // The loop comparison proves the upper bound and the array reference
        // stays stable. A signed negative index can still enter i < Length.
        private void EmitProvenPackedIndex(int elementBytes) {
            if (!provenNonNegative) {
                code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xf6); // test rsi, rsi
                code.EmitByte(0x0f); code.EmitByte(0x89); int nonnegative = code.Position(); code.Emit32(0); // jns
                EmitRuntime("rt_index_error");
                PatchRelative(nonnegative, code.Position());
            }
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x44);
            if (elementBytes == 1) { code.EmitByte(0x37); }
            else { code.EmitByte(0xb7); }
            code.EmitByte(8);
        }

        private void EmitProvenPackedRead(int indexSlot, int elementBytes) {
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0xb5);
            code.Emit32(-8 * (indexSlot + 1)); // mov rsi, [rbp-offset]
            if (!provenNonNegative) {
                code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xf6); // test rsi, rsi
                code.EmitByte(0x0f); code.EmitByte(0x89); int nonnegative = code.Position(); code.Emit32(0);
                EmitRuntime("rt_index_error");
                PatchRelative(nonnegative, code.Position());
            }
            if (elementBytes == 1) {
                code.EmitByte(0x0f); code.EmitByte(0xb6); code.EmitByte(0x44);
                code.EmitByte(0x30); code.EmitByte(8); // movzx eax, byte [rax + rsi + 8]
            } else {
                code.EmitByte(0x48); code.EmitByte(0x63); code.EmitByte(0x44);
                code.EmitByte(0xb0); code.EmitByte(8); // movsxd rax, dword [rax + rsi * 4 + 8]
            }
        }

        private void MoveRdiRax() { code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc7); }
        private void DropSlots(int slots) {
            if (slots != 0) { code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xc4); code.Emit32(slots * 8); }
        }

        private void EmitLiteral(string text) {
            int index = AddPayload(text);
            if (freestanding) {
                // The kernel's explicit ownership rules require a fresh
                // managed string; rt_string copies raw image bytes into it.
                code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x3d); // lea rdi, [rip+literal]
                AddPayloadPatch(code.Position(), index); code.Emit32(0);
                code.EmitByte(0xbe); code.Emit32(text.Length); // mov esi, byte length
                EmitRuntime("rt_string");
            } else {
                // Linux literals include a length header in the ELF image.
                code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x05); // lea rax, [rip+literal]
                AddPayloadPatch(code.Position(), index); code.Emit32(0);
            }
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
            return CompileFieldAddressWithReceiver(receiver, name, resolvedOwner, false);
        }
        private bool CompileFieldAddressWithReceiver(IrExpression receiver, string name, string resolvedOwner, bool receiverAlreadyLoaded) {
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
                if (!receiverAlreadyLoaded && !CompileExpression(receiver)) { return false; }
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
            int assignmentOp = expression.AssignmentOperatorKind();
            bool compound = assignmentOp != IrOperator.EqualsToken();
            bool returnsOld = expression.ReturnsOld();
            int slot = -1;
            string expected = "";
            bool packedByteTarget = false;
            bool packedIntTarget = false;
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
                    packedByteTarget = !freestanding && valueType == "byte[]";
                    packedIntTarget = !freestanding && valueType == "int[]";
                    expected = ElementType(valueType);
                    if (!CompileIndexOperands(target.Index())) { return false; }
                    if (packedByteTarget) {
                        if (ProvenPackedAccess(target.Receiver(), target.Index())) { EmitProvenPackedIndex(1); }
                        else { EmitCheckedPackedIndex(1); }
                    }
                    else if (packedIntTarget) {
                        if (ProvenPackedAccess(target.Receiver(), target.Index())) { EmitProvenPackedIndex(4); }
                        else { EmitCheckedPackedIndex(4); }
                    }
                    else { EmitRuntime("rt_index"); }
                    valueType = expected;
                } else { failure = "unsupported native assignment target"; return false; }
                expected = valueType;
                code.EmitByte(0x50); // retain interior lvalue pointer as a GC root during RHS evaluation
            }
            if (compound) {
                if (!PrimitiveNumeric(expected)) { failure = "native compound assignment requires an integral target"; return false; }
                if (slot >= 0) { EmitLoadLocal(slot); }
                else if (packedByteTarget) {
                    code.EmitByte(0x0f); code.EmitByte(0xb6); code.EmitByte(0x00); // movzx eax, byte [rax]
                } else if (packedIntTarget) {
                    code.EmitByte(0x8b); code.EmitByte(0x00); // mov eax, [rax]
                    NormalizeRax(expected);
                } else {
                    code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x00); // mov rax, [rax]
                    NormalizeRax(expected);
                }
                if (returnsOld) { code.EmitByte(0x50); } // result of postfix update
                code.EmitByte(0x50); // preserve old value while evaluating RHS
            }
            if (!CompileExpression(expression.Value())) { return false; }
            if (compound) {
                if (!PrimitiveNumeric(valueType)) { failure = "native compound assignment requires an integral value"; return false; }
                NormalizeRax(expected);
                code.EmitByte(0x59); // old value in rcx, RHS in rax
                if (assignmentOp == IrOperator.PlusEqualsToken()) {
                    code.EmitByte(0x48); code.EmitByte(0x01); code.EmitByte(0xc8); // add rax, rcx
                } else if (assignmentOp == IrOperator.MinusEqualsToken()) {
                    code.EmitByte(0x48); code.EmitByte(0x29); code.EmitByte(0xc1); // sub rcx, rax
                    code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc8); // mov rax, rcx
                } else if (assignmentOp == IrOperator.StarEqualsToken()) {
                    code.EmitByte(0x48); code.EmitByte(0x0f); code.EmitByte(0xaf); code.EmitByte(0xc8); // imul rcx, rax
                    code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc8); // mov rax, rcx
                } else if (assignmentOp == IrOperator.SlashEqualsToken() || assignmentOp == IrOperator.PercentEqualsToken()) {
                    code.EmitByte(0x48); code.EmitByte(0x91); // xchg rax, rcx
                    if (Unsigned(expected)) {
                        code.EmitByte(0x31); code.EmitByte(0xd2); // xor edx, edx
                        code.EmitByte(0x48); code.EmitByte(0xf7); code.EmitByte(0xf1); // div rcx
                    } else {
                        code.EmitByte(0x48); code.EmitByte(0x99); // cqo
                        code.EmitByte(0x48); code.EmitByte(0xf7); code.EmitByte(0xf9); // idiv rcx
                    }
                    if (assignmentOp == IrOperator.PercentEqualsToken()) {
                        code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xd0); // mov rax, rdx
                    }
                } else if (assignmentOp == IrOperator.AmpersandEqualsToken() ||
                           assignmentOp == IrOperator.PipeEqualsToken() || assignmentOp == IrOperator.CaretEqualsToken()) {
                    code.EmitByte(0x48);
                    if (assignmentOp == IrOperator.AmpersandEqualsToken()) { code.EmitByte(0x21); }
                    if (assignmentOp == IrOperator.PipeEqualsToken()) { code.EmitByte(0x09); }
                    if (assignmentOp == IrOperator.CaretEqualsToken()) { code.EmitByte(0x31); }
                    code.EmitByte(0xc8); // operation rax, rcx
                } else if (assignmentOp == IrOperator.ShiftLeftEqualsToken() ||
                           assignmentOp == IrOperator.ShiftRightEqualsToken()) {
                    code.EmitByte(0x48); code.EmitByte(0x91); // value in rax, count in rcx
                    code.EmitByte(0x83); code.EmitByte(0xe1); code.EmitByte(NumericBits(expected) - 1);
                    code.EmitByte(0x48); code.EmitByte(0xd3);
                    if (assignmentOp == IrOperator.ShiftLeftEqualsToken()) { code.EmitByte(0xe0); }
                    else if (Unsigned(expected)) { code.EmitByte(0xe8); }
                    else { code.EmitByte(0xf8); }
                } else { failure = "unsupported native compound assignment operator"; return false; }
            } else if (!Assignable(valueType, expected)) { failure = "native assignment type mismatch"; return false; }
            // Numeric binary expressions already normalize their result to
            // their declared type. Avoid emitting the same extension twice
            // when storing that result to a matching target.
            bool normalizedBinary = false;
            if (!compound && PrimitiveNumeric(expected) && valueType == expected &&
                expression.Value().Kind() == IrExpression.KindBinary()) {
                int rhsOp = expression.Value().OperatorKind();
                normalizedBinary = rhsOp == IrOperator.PlusToken() || rhsOp == IrOperator.MinusToken() ||
                    rhsOp == IrOperator.StarToken() || rhsOp == IrOperator.SlashToken() ||
                    rhsOp == IrOperator.PercentToken() || rhsOp == IrOperator.AmpersandToken() ||
                    rhsOp == IrOperator.PipeToken() || rhsOp == IrOperator.CaretToken() ||
                    rhsOp == IrOperator.ShiftLeftToken() || rhsOp == IrOperator.ShiftRightToken();
            }
            if (!normalizedBinary) { PrepareValue(expected); }
            if (slot >= 0) {
                EmitStoreLocal(slot);
                InvalidateArrayLengthSource(slot);
                if (returnsOld) { code.EmitByte(0x58); } // pop original value into rax
            }
            else {
                if (returnsOld) { code.EmitByte(0x5a); } // original value in rdx
                code.EmitByte(0x59);
                if (packedByteTarget) { code.EmitByte(0x88); code.EmitByte(0x01); }
                else if (packedIntTarget) { code.EmitByte(0x89); code.EmitByte(0x01); }
                else { code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x01); }
                if (returnsOld) { code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xd0); } // mov rax, rdx
            }
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

        private void EmitLoadLocalRcx(int slot) {
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x8d); code.Emit32(-8 * (slot + 1)); // mov rcx, [rbp-offsetof]
        }

        private int EmitJumpIfZero() {
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xc0); // test rax, rax
            code.EmitByte(0x0f); code.EmitByte(0x84); // je rel32
            int patch = code.Position();
            code.Emit32(0);
            return patch;
        }

        private void FinishOptional(int skipPatch) {
            int endPatch = EmitJump();
            PatchRelative(skipPatch, code.Position());
            code.EmitByte(0x31); code.EmitByte(0xc0); // xor eax, eax
            PatchRelative(endPatch, code.Position());
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
            if (windows) { EmitRuntime("win_syscall"); }
            else { code.EmitByte(0x0f); code.EmitByte(0x05); } // Linux syscall
        }

        private void InvalidateArrayLengthSource(int changedSlot) {
            int i = 0;
            while (i < localCount) {
                if (i == changedSlot || arrayLengthSourceSlots[i] == changedSlot) {
                    arrayLengthSourceSlots[i] = -1;
                }
                i = i + 1;
            }
        }

        private int AddLocal(string name, string type) {
            int i = scopeStart;
            while (i < localCount) {
                if (localNames[i] == name) { failure = "duplicate native local: " + name; return -1; }
                i = i + 1;
            }
            localNames = AppendString(localNames, localCount, name);
            localTypes = AppendString(localTypes, localCount, type);
            arrayLengthSourceSlots = AppendInt(arrayLengthSourceSlots, localCount, -1);
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
