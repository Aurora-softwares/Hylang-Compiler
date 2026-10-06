namespace Hydrogen.Compiler.IR {
    public class IrOp {
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

        public IrOp(int inputKind, string inputText, int inputExitCode) {
            kind = inputKind;
            text = inputText;
            exitCode = inputExitCode;
        }

        public int Kind() { return kind; }
        public string Text() { return text; }
        public int ExitCode() { return exitCode; }
    }

    public class IrEntryPoint {
        private IrOp[] ops;

        public IrEntryPoint(IrOp[] inputOps) {
            ops = inputOps;
        }

        public IrOp[] Ops() {
            return ops;
        }

        public string ToDebugText() {
            string text = "IrEntryPoint\n";
            int i = 0;
            while (i < ops.Length) {
                if (ops[i].Kind() == IrOp.KindWriteLineLiteral()) {
                    text = text + "  WriteLineLiteral(\"" + ops[i].Text() + "\")\n";
                } else if (ops[i].Kind() == IrOp.KindStartImageLiteral()) {
                    text = text + "  StartImageLiteral(\"" + ops[i].Text() + "\")\n";
                } else if (ops[i].Kind() == IrOp.KindExitBootServices()) {
                    text = text + "  ExitBootServices()\n";
                } else if (ops[i].Kind() == IrOp.KindKernelHalt()) {
                    text = text + "  KernelHalt()\n";
                } else if (ops[i].Kind() == IrOp.KindInitializeMemoryMap()) {
                    text = text + "  MemoryMap.Initialize()\n";
                } else if (ops[i].Kind() == IrOp.KindInitializeKernelMemory()) {
                    text = text + "  Memory.Initialize()\n";
                } else if (ops[i].Kind() == IrOp.KindInitializeVirtualMemory()) {
                    text = text + "  VirtualMemory.Initialize()\n";
                } else if (ops[i].Kind() == IrOp.KindExit()) {
                    text = text + "  Exit(" + ops[i].ExitCode() + ")\n";
                } else {
                    text = text + "  <unknown-op>\n";
                }
                i = i + 1;
            }
            return text;
        }
    }
}
