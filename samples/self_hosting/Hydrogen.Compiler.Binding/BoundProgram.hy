using Hydrogen.Compiler.IR;

namespace Hydrogen.Compiler.Binding {
    public class BoundOp {
        public static int KindWriteLineLiteral() { return 1; }
        public static int KindExit() { return 2; }
        public static int KindStartImageLiteral() { return 3; }
        public static int KindExitBootServices() { return 4; }
        public static int KindKernelHalt() { return 5; }
        public static int KindInitializeMemoryMap() { return 6; }
        public static int KindInitializeKernelMemory() { return 7; }
        public static int KindInitializeVirtualMemory() { return 8; }

        private int kind;
        private string text;
        private int exitCode;

        public BoundOp(int inputKind, string inputText, int inputExitCode) {
            kind = inputKind;
            text = inputText;
            exitCode = inputExitCode;
        }

        public int Kind() {
            return kind;
        }

        public string Text() {
            return text;
        }

        public int ExitCode() {
            return exitCode;
        }
    }

    public class BoundProgram {
        private IrModule module;
        public IrModule Module() { return module; }
        public void SetModule(IrModule value) { module = value; }
        private MethodSymbol[] methods;
        private BoundOp[] entryOps;

        public BoundProgram(MethodSymbol[] inputMethods, BoundOp[] inputEntryOps) {
            methods = inputMethods;
            entryOps = inputEntryOps;
        }

        public MethodSymbol[] Methods() {
            return methods;
        }

        public BoundOp[] EntryOps() {
            return entryOps;
        }

        public string ToDebugText() {
            string text = "BoundProgram\n";
            int i = 0;
            while (i < methods.Length) {
                MethodSymbol method = methods[i];
                text = text + "  method " + method.Name() + " : " + method.ReturnType().Name() + "\n";
                int p = 0;
                ParameterSymbol[] parameters = method.Parameters();
                while (p < parameters.Length) {
                    text = text + "    param " + parameters[p].Name() + " : " + parameters[p].Type().Name() + "\n";
                    p = p + 1;
                }
                i = i + 1;
            }
            text = text + "EntryPoint\n";
            int o = 0;
            while (o < entryOps.Length) {
                if (entryOps[o].Kind() == BoundOp.KindWriteLineLiteral()) {
                    text = text + "  WriteLineLiteral(\"" + entryOps[o].Text() + "\")\n";
                } else if (entryOps[o].Kind() == BoundOp.KindStartImageLiteral()) {
                    text = text + "  StartImageLiteral(\"" + entryOps[o].Text() + "\")\n";
                } else if (entryOps[o].Kind() == BoundOp.KindExitBootServices()) {
                    text = text + "  ExitBootServices()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindKernelHalt()) {
                    text = text + "  KernelHalt()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindInitializeMemoryMap()) {
                    text = text + "  MemoryMap.Initialize()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindInitializeKernelMemory()) {
                    text = text + "  Memory.Initialize()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindInitializeVirtualMemory()) {
                    text = text + "  VirtualMemory.Initialize()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindExit()) {
                    text = text + "  Exit(" + entryOps[o].ExitCode() + ")\n";
                } else {
                    text = text + "  <unknown-op>\n";
                }
                o = o + 1;
            }
            return text;
        }
    }
}
