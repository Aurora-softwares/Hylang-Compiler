namespace Hydrogen.Compiler.CodeGen.X64 {
    // Generic x86-64 Mach-O relocatable object writer.
    // Input comes from DirectMainCompiler; this class never parses source code.
    // The output is MH_OBJECT, to be linked against macOS libSystem.
    public class MacOSImageBuilder {
        public byte[] BuildCodeAndData(byte[] code, string[] payloads, int[] patchOffsets, int[] payloadIndexes, int[] externalCallOffsets, string[] externalSymbols, int runtimeStart, WindowsRuntimeEmitter runtime) {
            if (code == null || payloads == null || patchOffsets == null || payloadIndexes == null || externalCallOffsets == null || externalSymbols == null) {
				return null;
			}
            if (code.Length < 1 || code.Length > 0x10000000 || patchOffsets.Length != payloadIndexes.Length || externalCallOffsets.Length != externalSymbols.Length) {
				return null;
			}

            // Initial representation: instructions and immutable managed strings
            // share a single __TEXT,__text section. Because they belong to the
            // same section, intra-section RIP-relative references are stable
            // across linking and can be resolved here without relocations.
            int[] payloadOffsets = new int[payloads.Length];
            int payloadBytes = 0;
            int i = 0;
            while (i < payloads.Length) {
                if (payloads[i] == null || payloadBytes > 0x10000000 - payloads[i].Length - 9) {
                    return null;
                }
                payloadOffsets[i] = payloadBytes;
                payloadBytes = payloadBytes + 8 + payloads[i].Length + 1;
                i = i + 1;
            }
            int sectionBytes = code.Length + payloadBytes;
            if (sectionBytes > 0x10000000) { return null; }

            // Patch the compiler's disp32 slots to point at Hydrogen strings.
            i = 0;
            while (i < patchOffsets.Length) {
                int site = patchOffsets[i];
                int index = payloadIndexes[i];
                if (site < 0 || site > code.Length - 4 ||
                    index < 0 || index >= payloadOffsets.Length) { return null; }
                int target = code.Length + payloadOffsets[index];
                Write32(code, site, target - (site + 4));
                i = i + 1;
            }

            // Every unresolved x86-64 call rel32 has an external-symbol
            // X86_64_RELOC_BRANCH relocation. For now, symbols may repeat;
            // this is correct but a subsequent pass can deduplicate them.
            int relocationCount = externalCallOffsets.Length;
            i = 0;
            while (i < relocationCount) {
                int site = externalCallOffsets[i];
                if (site < 0 || site > code.Length - 4 ||
                    externalSymbols[i] == null || externalSymbols[i].Length == 0) {
                    return null;
                }
                Write32(code, site, 0);
                i = i + 1;
            }

            int stringBytes = 7; // leading NUL, "_main", trailing NUL
            i = 0;
            while (i < externalSymbols.Length) {
                if (stringBytes > 0x10000000 - externalSymbols[i].Length - 1) {
                    return null;
                }
                stringBytes = stringBytes + externalSymbols[i].Length + 1;
                i = i + 1;
            }

            // mach_header_64 + LC_SEGMENT_64 (one section) + LC_SYMTAB
            // + LC_BUILD_VERSION. All output is little-endian.
            int commandBytes = 152 + 24 + 24;
            int sectionOffset = Align(32 + commandBytes, 16);
            int relocationOffset = Align(sectionOffset + sectionBytes, 4);
            int symbolOffset = Align(relocationOffset + relocationCount * 8, 8);
            int symbolCount = 1 + relocationCount; // _main plus imports
            int stringOffset = symbolOffset + symbolCount * 16;
            int totalBytes = stringOffset + stringBytes;
            if (totalBytes < 0 || totalBytes > 0x20000000) { return null; }
            byte[] image = new byte[totalBytes];

            // mach_header_64: MH_MAGIC_64, CPU_TYPE_X86_64, MH_OBJECT
            Write32(image, 0, -17958193); // 0xFEEDFACF
            Write32(image, 4, 16777223);  // 0x01000007
            Write32(image, 8, 3);         // CPU_SUBTYPE_X86_64_ALL
            Write32(image, 12, 1);        // MH_OBJECT
            Write32(image, 16, 3);        // ncmds
            Write32(image, 20, commandBytes);

            // LC_SEGMENT_64, with one __TEXT,__text section.
            int segment = 32;
            Write32(image, segment, 25);
            Write32(image, segment + 4, 152);
            Write64(image, segment + 32, sectionBytes); // vmsize
            Write64(image, segment + 40, sectionOffset);
            Write64(image, segment + 48, sectionBytes);
            Write32(image, segment + 56, 7);
            Write32(image, segment + 60, 7);
            Write32(image, segment + 64, 1); // nsects

            int section = segment + 72;
            WriteAscii(image, section, "__text");
            WriteAscii(image, section + 16, "__TEXT");
            Write64(image, section + 40, sectionBytes);
            Write32(image, section + 48, sectionOffset);
            Write32(image, section + 52, 4); // align 2^4
            if (relocationCount > 0) {
                Write32(image, section + 56, relocationOffset);
                Write32(image, section + 60, relocationCount);
            }
            Write32(image, section + 64, -2147482624); // S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS

            int symCommand = segment + 152;
            Write32(image, symCommand, 2); // LC_SYMTAB
            Write32(image, symCommand + 4, 24);
            Write32(image, symCommand + 8, symbolOffset);
            Write32(image, symCommand + 12, symbolCount);
            Write32(image, symCommand + 16, stringOffset);
            Write32(image, symCommand + 20, stringBytes);

            int version = symCommand + 24;
            Write32(image, version, 50); // LC_BUILD_VERSION
            Write32(image, version + 4, 24);
            Write32(image, version + 8, 1); // PLATFORM_MACOS
            Write32(image, version + 12, 720896); // macOS 11.0
            Write32(image, version + 16, 720896);

            i = 0;
            while (i < code.Length) {
                image[sectionOffset + i] = code[i];
                i = i + 1;
            }
            i = 0;
            while (i < payloads.Length) {
                int dest = sectionOffset + code.Length + payloadOffsets[i];
                Write64(image, dest, payloads[i].Length);
                int j = 0;
                while (j < payloads[i].Length) {
                    image[dest + 8 + j] = (byte)System.Console.Utf8ByteAt(payloads[i], j);
                    j = j + 1;
                }
                i = i + 1;
            }

            // Symbol #0: external definition _main, at section offset 0.
            Write32(image, symbolOffset, 1);
            image[symbolOffset + 4] = (byte)15; // N_SECT | N_EXT
            image[symbolOffset + 5] = (byte)1;  // section ordinal

            WriteAscii(image, stringOffset + 1, "_main");
            int namePosition = 7;
            i = 0;
            while (i < relocationCount) {
                int entry = symbolOffset + (i + 1) * 16;
                Write32(image, entry, namePosition);
                image[entry + 4] = (byte)1; // N_UNDF | N_EXT
                WriteAscii(image, stringOffset + namePosition, externalSymbols[i]);
                namePosition = namePosition + externalSymbols[i].Length + 1;

                int reloc = relocationOffset + i * 8;
                Write32(image, reloc, externalCallOffsets[i]);
                // X86_64_RELOC_BRANCH: type=2, extern=1, length=2,
                // pcrel=1, symbol index=(i+1).
                Write32(image, reloc + 4, 754974720 + i + 1);
                i = i + 1;
            }
            return image;
        }

        private int Align(int value, int unit) {
            return (value + unit - 1) / unit * unit;
        }

        private void WriteAscii(byte[] image, int offset, string value) {
            ElfImageBuilder ascii = new ElfImageBuilder();
            int i = 0;
            while (i < value.Length) {
                bytes[offset + i] = (byte)ascii.AsciiCode(value[i]);
                i = i + 1;
            }
        }

        private void Write16(byte[] image, int offset, int value) {
            WriteByte(image, offset, value % 256);
            WriteByte(image, offset + 1, (value / 256) % 256);
        }

        private void Write32(byte[] image, int offset, int value) {
            int current = value;
            int i = 0;
            while (i < 4) {
                int part = current % 256;
                if (part < 0) { part = part + 256; }
                WriteByte(image, offset + i, part);
                current = (current - part) / 256;
                i = i + 1;
            }
        }

        private void Write64(byte[] image, int offset, int value) {
            Write32(image, offset, value);
            Write32(image, offset + 4, 0);
        }

        private void WriteByte(byte[] image, int offset, int value) {
            image[offset] = (byte)value;
        }
    }
}
