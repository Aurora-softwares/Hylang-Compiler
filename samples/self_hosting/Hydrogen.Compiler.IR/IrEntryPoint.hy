namespace Hydrogen.Compiler.IR {
    public class IrOp {
        public static int KindWriteLineLiteral() { return 1; }
        public static int KindExit() { return 2; }

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
