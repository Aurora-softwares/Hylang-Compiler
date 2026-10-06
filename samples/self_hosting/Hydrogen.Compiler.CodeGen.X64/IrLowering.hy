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
                } else if (ops[i].Kind() == BoundOp.KindStartImageLiteral()) {
                    lowered[i] = new IrOp(IrOp.KindStartImageLiteral(), ops[i].Text(), 0);
                } else if (ops[i].Kind() == BoundOp.KindExitBootServices()) {
                    lowered[i] = new IrOp(IrOp.KindExitBootServices(), "", 0);
                } else if (ops[i].Kind() == BoundOp.KindKernelHalt()) {
                    lowered[i] = new IrOp(IrOp.KindKernelHalt(), "", 0);
                } else if (ops[i].Kind() == BoundOp.KindInitializeMemoryMap()) {
                    lowered[i] = new IrOp(IrOp.KindInitializeMemoryMap(), "", 0);
                } else if (ops[i].Kind() == BoundOp.KindInitializeKernelMemory()) {
                    lowered[i] = new IrOp(IrOp.KindInitializeKernelMemory(), "", 0);
                } else if (ops[i].Kind() == BoundOp.KindInitializeVirtualMemory()) {
                    lowered[i] = new IrOp(IrOp.KindInitializeVirtualMemory(), "", 0);
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
