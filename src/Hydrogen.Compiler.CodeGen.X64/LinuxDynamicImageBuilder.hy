using Hydrogen.Compiler.IR;

namespace Hydrogen.Compiler.CodeGen.X64 {
    // The Linux native linker writes a dynamic ELF directly in Hydrogen.
    // It deliberately has no C/C++ compiler, assembler, objcopy or linker step.
    // Imported C ABI functions are resolved by the system's ELF loader.
    public class LinuxDynamicImageBuilder {
        private static int Align(int number, int boundary) {
            return ((number + boundary - 1) / boundary) * boundary;
        }

        public byte[] Build(byte[] code, string[] literals, int[] literalPatches,
                            int[] literalIndexes, string[] symbols, int[] symbolPatches,
                            int[] symbolIndexes) {
            if (symbols.Length == 0 || symbols.Length != symbolPatches.Length) {
                // More than one reference to a symbol is permitted; only the
                // symbol-index array and patch array must be equally sized.
                if (symbols.Length == 0 || symbolPatches.Length != symbolIndexes.Length) {
                    return null;
                }
            }
            if (literalPatches.Length != literalIndexes.Length) { return null; }
            string interpreter = "/lib64/ld-linux-x86-64.so.2";
            int phnum = 5;
            int phOffset = 64;
            int interpOffset = phOffset + phnum * 56;
            int codeOffset = Align(interpOffset + interpreter.Length + 1, 16);
            int p = 0;
            int at = codeOffset + code.Length;
            int[] literalOffsets = new int[literals.Length];
            while (p < literals.Length) {
                literalOffsets[p] = at;
                at = at + 8 + literals[p].Length + 1;
                p = p + 1;
            }
            // The first string-table byte is the empty symbol name.
            int strOffset = Align(at, 8);
            int strSize = 1;
            string gtk = "libgtk-4.so.1";
            string glib = "libglib-2.0.so.0";
            string gobject = "libgobject-2.0.so.0";
            int gtkName = strSize; strSize = strSize + gtk.Length + 1;
            int glibName = strSize; strSize = strSize + glib.Length + 1;
            int gobjectName = strSize; strSize = strSize + gobject.Length + 1;
            int[] names = new int[symbols.Length];
            p = 0;
            while (p < symbols.Length) {
                names[p] = strSize;
                strSize = strSize + symbols[p].Length + 1;
                p = p + 1;
            }
            int symOffset = Align(strOffset + strSize, 8);
            int hashOffset = Align(symOffset + (symbols.Length + 1) * 24, 8);
            // SysV hash: one bucket, a terminating chain for each symbol.
            int hashSize = (3 + symbols.Length + 1) * 4;
            int relaOffset = Align(hashOffset + hashSize, 8);
            int relaSize = symbols.Length * 24;
            int rwOffset = Align(relaOffset + relaSize, 4096);
            int dynamicOffset = rwOffset;
            int dynamicSize = 14 * 16; // DT_NEEDED x3, ELF tables, NULL
            int gotOffset = Align(dynamicOffset + dynamicSize, 8);
            int end = gotOffset + symbols.Length * 8;
            byte[] image = new byte[end];

            // ELF64 ET_EXEC with PT_INTERP, two W^X loads, PT_DYNAMIC and NX stack.
            image[0] = 127; image[1] = 69; image[2] = 76; image[3] = 70;
            image[4] = 2; image[5] = 1; image[6] = 1;
            U16(image, 16, 2); U16(image, 18, 62); U32(image, 20, 1);
            U64(image, 24, 0x400000 + codeOffset);
            U64(image, 32, phOffset);
            U16(image, 52, 64); U16(image, 54, 56); U16(image, 56, phnum);

            // PT_INTERP
            Header(image, phOffset, 3, 4, interpOffset,
                   interpreter.Length + 1, 1);
            // PT_LOAD RX
            Header(image, phOffset + 56, 1, 5, 0, rwOffset, 4096);
            // PT_LOAD RW
            Header(image, phOffset + 112, 1, 6,
                   rwOffset, end - rwOffset, 4096);
            // PT_DYNAMIC RW
            Header(image, phOffset + 168, 2, 6,
                   dynamicOffset, dynamicSize, 8);
            // PT_GNU_STACK RW / nonexecutable
            U32(image, phOffset + 224, 0x6474e551);
            U32(image, phOffset + 228, 6);
            U64(image, phOffset + 272, 16);

            Raw(image, interpOffset, interpreter);
            p = 0;
            while (p < code.Length) { image[codeOffset + p] = code[p]; p = p + 1; }

            p = 0;
            while (p < literals.Length) {
                string value = literals[p];
                U64(image, literalOffsets[p], value.Length);
                Raw(image, literalOffsets[p] + 8, value);
                p = p + 1;
            }
            p = 0;
            while (p < literalPatches.Length) {
                int target = literalOffsets[literalIndexes[p]];
                int site = literalPatches[p];
                Relative(code, site, codeOffset + site + 4, target);
                p = p + 1;
            }
            p = 0;
            while (p < symbolPatches.Length) {
                int index = symbolIndexes[p];
                if (index < 0 || index >= symbols.Length) { return null; }
                int site = symbolPatches[p];
                Relative(code, site, codeOffset + site + 4, gotOffset + index * 8);
                p = p + 1;
            }
            // Recopy the patched machine code after all RIP displacements resolve.
            p = 0;
            while (p < code.Length) { image[codeOffset + p] = code[p]; p = p + 1; }

            image[strOffset] = 0;
            Raw(image, strOffset + gtkName, gtk);
            Raw(image, strOffset + glibName, glib);
            Raw(image, strOffset + gobjectName, gobject);
            p = 0;
            while (p < symbols.Length) {
                Raw(image, strOffset + names[p], symbols[p]);
                int entry = symOffset + (p + 1) * 24;
                U32(image, entry, names[p]);
                image[entry + 4] = 18; // STB_GLOBAL | STT_FUNC
                // Undefined symbol: the runtime loader resolves this name.
                p = p + 1;
            }
            U32(image, hashOffset, 1);
            U32(image, hashOffset + 4, symbols.Length + 1);
            if (symbols.Length > 0) { U32(image, hashOffset + 8, 1); }

            p = 0;
            while (p < symbols.Length) {
                int entry = relaOffset + p * 24;
                U64(image, entry, 0x400000 + gotOffset + p * 8);
                U32(image, entry + 8, 6); // R_X86_64_GLOB_DAT
                U32(image, entry + 12, p + 1);
                p = p + 1;
            }
            // Dynamic tags use absolute virtual addresses, not file offsets.
            int d = dynamicOffset;
            d = Dynamic(image, d, 1, gtkName);
            d = Dynamic(image, d, 1, glibName);
            d = Dynamic(image, d, 1, gobjectName);
            d = Dynamic(image, d, 4, 0x400000 + hashOffset); // DT_HASH
            d = Dynamic(image, d, 5, 0x400000 + strOffset); // DT_STRTAB
            d = Dynamic(image, d, 6, 0x400000 + symOffset); // DT_SYMTAB
            d = Dynamic(image, d, 10, strSize); // DT_STRSZ
            d = Dynamic(image, d, 11, 24); // DT_SYMENT
            d = Dynamic(image, d, 7, 0x400000 + relaOffset); // DT_RELA
            d = Dynamic(image, d, 8, relaSize); // DT_RELASZ
            d = Dynamic(image, d, 9, 24); // DT_RELAENT
            d = Dynamic(image, d, 0, 0);
            return image;
        }

        private void Header(byte[] bytes, int site, int kind, int flags,
                            int offset, int size, int alignment) {
            U32(bytes, site, kind);
            U32(bytes, site + 4, flags);
            U64(bytes, site + 8, offset);
            U64(bytes, site + 16, 0x400000 + offset);
            U64(bytes, site + 24, 0x400000 + offset);
            U64(bytes, site + 32, size);
            U64(bytes, site + 40, size);
            U64(bytes, site + 48, alignment);
        }
        private int Dynamic(byte[] bytes, int at, int tag, int value) {
            U64(bytes, at, tag);
            U64(bytes, at + 8, value);
            return at + 16;
        }
        private void Raw(byte[] bytes, int offset, string text) {
            int i = 0;
            while (i < text.Length) {
                bytes[offset + i] = (byte)System.Console.Utf8ByteAt(text, i);
                i = i + 1;
            }
        }
        private void Relative(byte[] bytes, int site, int next, int target) {
            int value = target - next;
            int i = 0;
            while (i < 4) {
                int b = value % 256;
                if (b < 0) { b = b + 256; }
                bytes[site + i] = (byte)b;
                if (value < 0) { value = (value - 255) / 256; }
                else { value = value / 256; }
                i = i + 1;
            }
        }
        private void U16(byte[] bytes, int at, int number) {
            bytes[at] = (byte)(number % 256);
            bytes[at + 1] = (byte)((number / 256) % 256);
        }
        private void U32(byte[] bytes, int at, int number) {
            int n = number;
            int i = 0;
            while (i < 4) {
                bytes[at + i] = (byte)(n % 256);
                n = n / 256;
                i = i + 1;
            }
        }
        private void U64(byte[] bytes, int at, int number) {
            U32(bytes, at, number); U32(bytes, at + 4, 0);
        }
    }
}
