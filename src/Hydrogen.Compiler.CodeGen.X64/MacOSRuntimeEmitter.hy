namespace Hydrogen.Compiler.CodeGen.X64 {
    // Initial generic macOS x86-64 runtime. It deliberately implements only
    // rt_init, rt_print and rt_exit. Add the remaining runtime helpers before
    // attempting to build the Hydrogen compiler on macOS.
    // External calls are Mach-O relocations resolved by the macOS linker.
    public class MacOSRuntimeEmitter {
        private int initOffset;
        private int printOffset;
        private int exitOffset;
        private int[] callOffsets;
        private string[] callSymbols;
        private int callCount;

        public MacOSRuntimeEmitter() {
            callOffsets = new int[3];
            callSymbols = new string[3];
            callCount = 0;
        }

        private void ImportCall(X64Assembler code, string symbol) {
            code.EmitByte(0xe8); // call rel32, relocatable
            callOffsets[callCount] = code.Position();
            callSymbols[callCount] = symbol;
            callCount = callCount + 1;
            code.Emit32(0);
        }

        public void Emit(X64Assembler code) {
            callCount = 0;
            int start = code.Position();

            // rt_init: no managed-heap support in the initial runtime.
            // Literal string output does not require allocation.
            initOffset = code.Position() - start;
            code.EmitByte(0x45); code.EmitByte(0x31); code.EmitByte(0xff); // xor r15d,r15d
            code.EmitByte(0xc3); // ret

            // rt_print(rdi=Hydrogen string pointer, rsi=newline flag)
            // String layout: [8-byte UTF-8 byte count][data bytes][NUL].
            printOffset = code.Position() - start;
            code.EmitByte(0x53); // push rbx
            code.EmitByte(0x41); code.EmitByte(0x54); // push r12
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xe4); // mov r12,rsp
            code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xe4); code.EmitByte(0xf0); // and rsp,-16
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xf3); // mov rbx,rsi
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x17); // mov rdx,[rdi]
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x77); code.EmitByte(0x08); // lea rsi,[rdi+8]
            code.EmitByte(0xbf); code.Emit32(1); // mov edi,1
            ImportCall(code, "_write");
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xdb); // test rbx,rbx
            code.EmitByte(0x0f); code.EmitByte(0x84);
            int skipNewlinePatch = code.Position(); code.Emit32(0);
            code.EmitByte(0xbf); code.Emit32(1); // mov edi,1
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x35);
            int newlinePatch = code.Position(); code.Emit32(0); // lea rsi,[rip+newline]
            code.EmitByte(0xba); code.Emit32(1); // mov edx,1
            ImportCall(code, "_write");
            int done = code.Position();
            code.Patch32(skipNewlinePatch, done - (skipNewlinePatch + 4));
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xe4); // mov rsp,r12
            code.EmitByte(0x41); code.EmitByte(0x5c); // pop r12
            code.EmitByte(0x5b); // pop rbx
            code.EmitByte(0xc3); // ret
            int newlineAddress = code.Position();
            code.EmitByte(10);
            code.Patch32(newlinePatch, newlineAddress - (newlinePatch + 4));

            // rt_exit(rdi=exit status), never returns.
            exitOffset = code.Position() - start;
            code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xe4); code.EmitByte(0xf0); // and rsp,-16
            ImportCall(code, "_exit");
            code.EmitByte(0x0f); code.EmitByte(0x0b); // ud2: _exit must not return
        }

        public int Offset(string helper) {
            if (helper == "rt_init") { return initOffset; }
            if (helper == "rt_print") { return printOffset; }
            if (helper == "rt_exit") { return exitOffset; }
            return -1; // Unsupported helpers fail compilation explicitly.
        }

        public int[] ExternalCallOffsets() {
            int[] result = new int[callCount];
            int i = 0;
            while (i < callCount) {
                result[i] = callOffsets[i];
                i = i + 1;
            }
            return result;
        }

        public string[] ExternalSymbols() {
            string[] result = new string[callCount];
            int i = 0;
            while (i < callCount) {
                result[i] = callSymbols[i];
                i = i + 1;
            }
            return result;
        }
    }
}
