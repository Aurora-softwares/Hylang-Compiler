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
                } else if (ops[i].Kind() == BoundOp.KindApplyKernelMappingPolicy()) {
                    lowered[i] = new IrOp(IrOp.KindApplyKernelMappingPolicy(), "", 0);
                } else if (ops[i].Kind() == BoundOp.KindAllocateKernelPage()) {
                    lowered[i] = new IrOp(IrOp.KindAllocateKernelPage(), "", 0);
                } else if (ops[i].Kind() == BoundOp.KindInitializeKernelHeap()) {
                    lowered[i] = new IrOp(IrOp.KindInitializeKernelHeap(), "", 0);
                } else if (ops[i].Kind() == BoundOp.KindAllocateKernelHeap()) {
                    lowered[i] = new IrOp(IrOp.KindAllocateKernelHeap(), "", ops[i].ExitCode());
                } else if (ops[i].Kind() == BoundOp.KindInitializeFramebuffer()) {
                    lowered[i] = new IrOp(IrOp.KindInitializeFramebuffer(), "", 0);
                } else if (ops[i].Kind() == BoundOp.KindFramebufferWriteLineLiteral()) {
                    lowered[i] = new IrOp(IrOp.KindFramebufferWriteLineLiteral(), ops[i].Text(), 0);
                } else if (ops[i].Kind() == BoundOp.KindClearScreen()) {
                    lowered[i] = new IrOp(IrOp.KindClearScreen(), "", 0);
                } else if (ops[i].Kind() == BoundOp.KindAwaitKey()) {
                    lowered[i] = new IrOp(IrOp.KindAwaitKey(), "", 0);
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
