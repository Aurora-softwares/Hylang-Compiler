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
        public static int KindClearScreen() { return 9; }
        public static int KindAwaitKey() { return 10; }
        public static int KindApplyKernelMappingPolicy() { return 11; }
        public static int KindAllocateKernelPage() { return 12; }
        public static int KindInitializeKernelHeap() { return 13; }
        public static int KindAllocateKernelHeap() { return 14; }
        public static int KindInitializeFramebuffer() { return 15; }
        public static int KindFramebufferWriteLineLiteral() { return 16; }
        public static int KindInitializeGdt() { return 17; }
        public static int KindInitializeIdt() { return 18; }
        public static int KindInitializeInterruptController() { return 19; }
        public static int KindInitializeTimer() { return 20; }
        public static int KindEnableInterrupts() { return 21; }
        public static int KindInterruptIdle() { return 22; }
        public static int KindInitializePci() { return 23; }
        public static int KindInitializeMmio() { return 24; }
        public static int KindInitializeDma() { return 25; }
        public static int KindAllocateDmaPages() { return 26; }
        public static int KindInitializeStorage() { return 27; }

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
                } else if (entryOps[o].Kind() == BoundOp.KindApplyKernelMappingPolicy()) {
                    text = text + "  VirtualMemory.ApplyPolicy()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindAllocateKernelPage()) {
                    text = text + "  Memory.AllocatePage()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindInitializeKernelHeap()) {
                    text = text + "  Heap.Initialize()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindAllocateKernelHeap()) {
                    text = text + "  Heap.Allocate(" + entryOps[o].ExitCode() + ")\n";
                } else if (entryOps[o].Kind() == BoundOp.KindInitializeFramebuffer()) {
                    text = text + "  Framebuffer.Initialize()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindFramebufferWriteLineLiteral()) {
                    text = text + "  Framebuffer.WriteLine(\"" + entryOps[o].Text() + "\")\n";
                } else if (entryOps[o].Kind() == BoundOp.KindInitializeGdt()) {
                    text = text + "  Gdt.Initialize()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindInitializeIdt()) {
                    text = text + "  Idt.Initialize()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindInitializeInterruptController()) {
                    text = text + "  Interrupts.Initialize()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindInitializeTimer()) {
                    text = text + "  Timer.Initialize()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindEnableInterrupts()) {
                    text = text + "  Interrupts.Enable()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindInterruptIdle()) {
                    text = text + "  Interrupts.Idle()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindInitializePci()) {
                    text = text + "  Pci.Initialize()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindInitializeMmio()) {
                    text = text + "  Mmio.Initialize()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindInitializeDma()) {
                    text = text + "  Dma.Initialize()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindAllocateDmaPages()) {
                    text = text + "  Dma.AllocatePages(" + entryOps[o].ExitCode() + ")\n";
                } else if (entryOps[o].Kind() == BoundOp.KindInitializeStorage()) {
                    text = text + "  Storage.Initialize()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindClearScreen()) {
                    text = text + "  Uefi.ClearScreen()\n";
                } else if (entryOps[o].Kind() == BoundOp.KindAwaitKey()) {
                    text = text + "  Uefi.Await()\n";
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
