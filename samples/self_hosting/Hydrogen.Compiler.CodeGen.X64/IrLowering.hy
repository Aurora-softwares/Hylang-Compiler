using Hydrogen.Compiler.Binding;

namespace Hydrogen.Compiler.IR {
    public class IrLowering {
        public IrModule Lower(BoundProgram program) {
            return program.Module();
        }

        public IrEntryPoint LowerEntryPoint(BoundProgram program) {
            BoundOp[] ops = program.EntryOps();
            IrOp[] lowered = new IrOp[ops.Length];
            int i = 0;
            while (i < ops.Length) {
                if (ops[i].Kind() == BoundOp.KindWriteLineLiteral()) {
                    lowered[i] = new IrOp(IrOp.KindWriteLineLiteral(), ops[i].Text(), 0);
                } else if (ops[i].Kind() == BoundOp.KindExit()) {
                    lowered[i] = new IrOp(IrOp.KindExit(), "", ops[i].ExitCode());
                } else {
                    lowered[i] = new IrOp(IrOp.KindExit(), "", 1);
                }
                i = i + 1;
            }
            return new IrEntryPoint(lowered);
        }
    }
}
