namespace Hydrogen.Compiler.CodeGen.X64 {
    // Direct Mach-O x86_64 executable writer, using libSystem and classic dyld
    // bind opcodes. No invocation of clang, ld, SDK tools or host linker.
    //
    // Layout: __PAGEZERO | __TEXT (code + strings + import stubs)
    //                     | __DATA (__got) | __LINKEDIT (binds + symbols).
    // Every runtime external call targets a local 6-byte RIP-relative stub;
    // dyld fills the matching GOT slot with the libSystem function address.
    public class MacOSImageBuilder {
        public byte[] BuildCodeAndData(byte[] code, string[] payloads,
                int[] patchOffsets, int[] payloadIndexes,
                int[] externalCallOffsets, string[] externalSymbols) {
            if (code == null || payloads == null || patchOffsets == null ||
                payloadIndexes == null || externalCallOffsets == null ||
                externalSymbols == null) { return null; }
            if (code.Length < 1 || code.Length > 0x10000000 ||
                patchOffsets.Length != payloadIndexes.Length ||
                externalCallOffsets.Length != externalSymbols.Length) { return null; }

            // Deduplicate imported function names while keeping their call sites.
            string[] imports = new string[externalSymbols.Length];
            int[] callImport = new int[externalSymbols.Length];
            int importCount = 0;
            int i = 0;
            while (i < externalSymbols.Length) {
                string name = externalSymbols[i];
                if (name == null || name.Length == 0 || name.Length > 4096) { return null; }
                int found = -1;
                int j = 0;
                while (j < importCount) {
                    if (imports[j] == name) { found = j; break; }
                    j = j + 1;
                }
                if (found < 0) {
                    found = importCount;
                    imports[importCount] = name;
                    importCount = importCount + 1;
                }
                callImport[i] = found;
                i = i + 1;
            }

            // Keep Hydrogen's existing inline managed-string representation.
            int[] payloadOffsets = new int[payloads.Length];
            int payloadBytes = 0;
            i = 0;
            while (i < payloads.Length) {
                if (payloads[i] == null || payloadBytes > 0x10000000 - payloads[i].Length - 9) {
                    return null;
                }
                payloadOffsets[i] = payloadBytes;
                payloadBytes = payloadBytes + payloads[i].Length + 9;
                i = i + 1;
            }

            // Import stubs are placed after generated instructions and strings.
            // Each stub: ff 25 <rip-relative disp32> = jmp [rip+disp32].
            if (importCount > 1000000) { return null; }
            int stubStart = code.Length + payloadBytes;
            int stubBytes = importCount * 6;
            if (stubStart > 0x10000000 - stubBytes) { return null; }
            int textBytes = stubStart + stubBytes;

            // Fixed x86-64 Mach-O command set (11 commands, 736 bytes).
            int commandBytes = 736;
            int textOffset = Align(32 + commandBytes, 16);
            int textFileSize = Align(textOffset + textBytes, 4096);
            int dataOffset = textFileSize;
            int dataFileSize = 4096;
            if (importCount > dataFileSize / 8) {
                dataFileSize = Align(importCount * 8, 4096);
            }
            int linkeditOffset = dataOffset + dataFileSize;

            int bindBytes = 3; // ordinal 1, pointer type, DONE
            int stringsBytes = 7; // leading NUL + _main + trailing NUL
            i = 0;
            while (i < importCount) {
                // SET_SYMBOL, name, NUL, SET_SEGMENT, slot ULEB, DO_BIND.
                bindBytes = bindBytes + imports[i].Length + 4 + UlebSize(i * 8);
                stringsBytes = stringsBytes + imports[i].Length + 1;
                i = i + 1;
            }
            int symOffset = Align(linkeditOffset + bindBytes, 8);
            int symbolCount = 1 + importCount;
            int stringOffset = symOffset + symbolCount * 16;
            int linkeditBytes = Align(stringOffset + stringsBytes - linkeditOffset, 16);
            int totalBytes = linkeditOffset + linkeditBytes;
            if (totalBytes < 0 || totalBytes > 0x20000000) { return null; }
            byte[] image = new byte[totalBytes];

            // mach_header_64: MH_EXECUTE, x86_64, NOUNDEFS|DYLDLINK|TWOLEVEL|PIE.
            Write32(image, 0, -17958193); // MH_MAGIC_64, 0xFEEDFACF
            Write32(image, 4, 16777223);  // CPU_TYPE_X86_64
            Write32(image, 8, 3);         // CPU_SUBTYPE_X86_64_ALL
            Write32(image, 12, 2);        // MH_EXECUTE
            Write32(image, 16, 11);       // ncmds
            Write32(image, 20, commandBytes);
            Write32(image, 24, 2097285); // flags 0x200085

            int at = 32;

            // LC_SEGMENT_64 #0: __PAGEZERO reserves address space below 4 GiB.
            Segment(image, at, "__PAGEZERO", 72, 0, 0, 0, 0, 0, 0, 0);
            Write64Parts(image, at + 32, 0, 1); // vmsize = 0x100000000
            at = at + 72;

            // LC_SEGMENT_64 #1: header, load commands, instructions, strings, stubs.
            Segment(image, at, "__TEXT", 152, 0, 1, textFileSize, 0,
                textFileSize, 7, 5);
            Write32(image, at + 64, 1); // one section
            int section = at + 72;
            WriteAscii(image, section, "__text");
            WriteAscii(image, section + 16, "__TEXT");
            Write64Parts(image, section + 32, textOffset, 1);
            Write64(image, section + 40, textBytes);
            Write32(image, section + 48, textOffset);
            Write32(image, section + 52, 4); // 16-byte alignment
            Write32(image, section + 64, -2147482624); // PURE|SOME_INSTRUCTIONS
            at = at + 152;

            // LC_SEGMENT_64 #2: writable GOT entries, resolved by dyld.
            Segment(image, at, "__DATA", 152, textFileSize, 1,
                dataFileSize, dataOffset, dataFileSize, 3, 3);
            Write32(image, at + 64, 1);
            section = at + 72;
            WriteAscii(image, section, "__got");
            WriteAscii(image, section + 16, "__DATA");
            Write64Parts(image, section + 32, dataOffset, 1);
            Write64(image, section + 40, importCount * 8);
            Write32(image, section + 48, dataOffset);
            Write32(image, section + 52, 3); // 8-byte alignment
            at = at + 152;

            // LC_SEGMENT_64 #3: dynamic binding stream and symbol tables.
            Segment(image, at, "__LINKEDIT", 72, linkeditOffset, 1,
                Align(linkeditBytes, 4096), linkeditOffset, linkeditBytes, 1, 1);
            at = at + 72;

            // LC_DYLD_INFO_ONLY; use non-lazy classic binding opcodes.
            Write32(image, at, -2147483614); // 0x80000022
            Write32(image, at + 4, 48);
            Write32(image, at + 16, linkeditOffset); // bind_off
            Write32(image, at + 20, bindBytes);      // bind_size
            at = at + 48;

            // LC_SYMTAB (main + imported symbols).
            Write32(image, at, 2);
            Write32(image, at + 4, 24);
            Write32(image, at + 8, symOffset);
            Write32(image, at + 12, symbolCount);
            Write32(image, at + 16, stringOffset);
            Write32(image, at + 20, stringsBytes);
            at = at + 24;

            // LC_DYSYMTAB: defined _main first, then imports.
            Write32(image, at, 11);
            Write32(image, at + 4, 80);
            Write32(image, at + 20, 1);           // nextdefsym
            Write32(image, at + 24, 1);           // iundefsym
            Write32(image, at + 28, importCount); // nundefsym
            at = at + 80;

            // LC_LOAD_DYLINKER: /usr/lib/dyld.
            Write32(image, at, 14);
            Write32(image, at + 4, 32);
            Write32(image, at + 8, 12);
            WriteAscii(image, at + 12, "/usr/lib/dyld");
            at = at + 32;

            // LC_LOAD_DYLIB: libSystem.B.dylib (no SDK or link step needed).
            Write32(image, at, 12);
            Write32(image, at + 4, 56);
            Write32(image, at + 8, 24);
            Write32(image, at + 16, 65536); // current version 1.0.0
            Write32(image, at + 20, 65536); // compatible version 1.0.0
            WriteAscii(image, at + 24, "/usr/lib/libSystem.B.dylib");
            at = at + 56;

            // LC_MAIN: __TEXT section begins at file offset textOffset.
            Write32(image, at, -2147483608); // 0x80000028
            Write32(image, at + 4, 24);
            Write64(image, at + 8, textOffset);
            at = at + 24;

            // LC_BUILD_VERSION: macOS 11.0, x86_64 (Rosetta-compatible).
            Write32(image, at, 50);
            Write32(image, at + 4, 24);
            Write32(image, at + 8, 1); // PLATFORM_MACOS
            Write32(image, at + 12, 720896); // minos 11.0
            Write32(image, at + 16, 720896); // sdk 11.0
            at = at + 24;
            if (at != textOffset) { return null; } // expected 32+736=768

            // Patch only internal rel32 references. The imported symbols use
            // local GOT-backed stubs, so no unresolved relocations remain.
            i = 0;
            while (i < patchOffsets.Length) {
                int site = patchOffsets[i];
                int index = payloadIndexes[i];
                if (site < 0 || site > code.Length - 4 ||
                    index < 0 || index >= payloadOffsets.Length) { return null; }
                Write32(code, site, code.Length + payloadOffsets[index] - site - 4);
                i = i + 1;
            }
            i = 0;
            while (i < externalCallOffsets.Length) {
                int site = externalCallOffsets[i];
                if (site < 0 || site > code.Length - 4) { return null; }
                int stub = stubStart + callImport[i] * 6;
                Write32(code, site, stub - site - 4);
                i = i + 1;
            }
            i = 0;
            while (i < code.Length) {
                image[textOffset + i] = code[i];
                i = i + 1;
            }
            i = 0;
            while (i < payloads.Length) {
                int dest = textOffset + code.Length + payloadOffsets[i];
                Write64(image, dest, payloads[i].Length);
                int j = 0;
                while (j < payloads[i].Length) {
                    image[dest + 8 + j] = (byte)System.Console.Utf8ByteAt(payloads[i], j);
                    j = j + 1;
                }
                i = i + 1;
            }
            i = 0;
            while (i < importCount) {
                int stubFile = textOffset + stubStart + i * 6;
                image[stubFile] = (byte)255;
                image[stubFile + 1] = (byte)37;
                // Relative displacement from the end of the stub to its GOT slot.
                Write32(image, stubFile + 2, dataOffset + i * 8 - stubFile - 6);
                i = i + 1;
            }

            // Immediate dyld binding: library ordinal #1 and pointer type.
            int bindAt = linkeditOffset;
            image[bindAt] = (byte)17; bindAt = bindAt + 1; // SET_DYLIB_ORDINAL_IMM(1)
            image[bindAt] = (byte)81; bindAt = bindAt + 1; // SET_TYPE_IMM(POINTER)
            i = 0;
            while (i < importCount) {
                image[bindAt] = (byte)64; bindAt = bindAt + 1; // SET_SYMBOL
                WriteAscii(image, bindAt, imports[i]);
                bindAt = bindAt + imports[i].Length + 1; // including terminator
                image[bindAt] = (byte)114; bindAt = bindAt + 1; // SEGMENT #2 (__DATA)
                bindAt = WriteUleb(image, bindAt, i * 8);
                image[bindAt] = (byte)144; bindAt = bindAt + 1; // DO_BIND
                i = i + 1;
            }
            image[bindAt] = (byte)0; bindAt = bindAt + 1; // DONE
            if (bindAt != linkeditOffset + bindBytes) { return null; }

            // nlist_64: external _main definition in __TEXT,__text.
            Write32(image, symOffset, 1); // string table offset
            image[symOffset + 4] = (byte)15; // N_SECT | N_EXT
            image[symOffset + 5] = (byte)1;  // __text section ordinal
            Write64Parts(image, symOffset + 8, textOffset, 1);
            WriteAscii(image, stringOffset + 1, "_main");
            int namePosition = 7;
            i = 0;
            while (i < importCount) {
                int entry = symOffset + (i + 1) * 16;
                Write32(image, entry, namePosition);
                image[entry + 4] = (byte)1; // N_UNDF | N_EXT
                Write16(image, entry + 6, 256); // libSystem ordinal 1
                WriteAscii(image, stringOffset + namePosition, imports[i]);
                namePosition = namePosition + imports[i].Length + 1;
                i = i + 1;
            }
            return image;
        }

        private void Segment(byte[] image, int at, string name, int size,
                int vmLow, int vmHigh, int vmSize, int fileOffset,
                int fileSize, int maxProt, int initProt) {
            Write32(image, at, 25); // LC_SEGMENT_64
            Write32(image, at + 4, size);
            WriteAscii(image, at + 8, name);
            Write64Parts(image, at + 24, vmLow, vmHigh);
            Write64(image, at + 32, vmSize);
            Write64(image, at + 40, fileOffset);
            Write64(image, at + 48, fileSize);
            Write32(image, at + 56, maxProt);
            Write32(image, at + 60, initProt);
        }

        private int Align(int value, int unit) {
            return (value + unit - 1) / unit * unit;
        }

        private int UlebSize(int value) {
            int count = 1;
            while (value >= 128) { value = value / 128; count = count + 1; }
            return count;
        }

        private int WriteUleb(byte[] image, int offset, int value) {
            int current = value;
            while (current >= 128) {
                image[offset] = (byte)((current % 128) + 128);
                offset = offset + 1;
                current = current / 128;
            }
            image[offset] = (byte)current;
            return offset + 1;
        }

        private void WriteAscii(byte[] image, int offset, string value) {
            ElfImageBuilder ascii = new ElfImageBuilder();
            int i = 0;
            while (i < value.Length) {
                image[offset + i] = (byte)ascii.AsciiCode(value[i]);
                i = i + 1;
            }
        }

        private void Write16(byte[] image, int offset, int value) {
            Write32Byte(image, offset, value);
            Write32Byte(image, offset + 1, value / 256);
        }

        private void Write32(byte[] image, int offset, int value) {
            int current = value;
            int i = 0;
            while (i < 4) {
                int part = current % 256;
                if (part < 0) { part = part + 256; }
                Write32Byte(image, offset + i, part);
                current = (current - part) / 256;
                i = i + 1;
            }
        }

        private void Write32Byte(byte[] image, int offset, int value) {
            image[offset] = (byte)(value % 256);
        }

        private void Write64(byte[] image, int offset, int value) {
            Write64Parts(image, offset, value, 0);
        }

        private void Write64Parts(byte[] image, int offset, int low32, int high32) {
            Write32(image, offset, low32);
            Write32(image, offset + 4, high32);
        }
    }
}