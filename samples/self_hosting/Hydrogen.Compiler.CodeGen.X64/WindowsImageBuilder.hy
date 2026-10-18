namespace Hydrogen.Compiler.CodeGen.X64 {
    public class WindowsImageBuilder {
        // Package the shared direct compiler's code and managed string literals
        // as a PE32+ console process. All references are RIP relative, including
        // the runtime's Win32 import thunks; no native linker is required.
        public byte[] BuildCodeAndData(byte[] code, string[] payloads,
                                       int[] patchOffsets, int[] payloadIndexes,
                                       int runtimeStart, WindowsRuntimeEmitter runtime) {
            if (code == null || code.Length < 1 || code.Length > 0x10000000) { return null; }
            int textRva = 0x1000;
            int textRaw = 0x200;
            int textSize = Align(code.Length, 0x200);
            int dataRva = Align(textRva + code.Length, 0x1000);
            int dataRaw = textRaw + textSize;
            int[] payloadOffsets = new int[payloads.Length];
            int dataLength = 0;
            int i = 0;
            while (i < payloads.Length) {
                payloadOffsets[i] = dataLength;
                dataLength = dataLength + 8 + payloads[i].Length + 1;
                i = i + 1;
            }
            if (dataLength == 0) { dataLength = 1; }
            int dataSize = Align(dataLength, 0x200);
            int importRva = Align(dataRva + dataLength, 0x1000);
            int importRaw = dataRaw + dataSize;

            string[] names = new string[17];
            names[0] = "VirtualAlloc"; names[1] = "VirtualFree";
            names[2] = "GetStdHandle"; names[3] = "WriteFile";
            names[4] = "ReadFile"; names[5] = "CreateFileW";
            names[6] = "CloseHandle"; names[7] = "SetFilePointerEx";
            names[8] = "GetConsoleMode"; names[9] = "CreateDirectoryW";
            names[10] = "GetLastError"; names[11] = "ExitProcess";
            names[12] = "GetCommandLineW"; names[13] = "CommandLineToArgvW";
            names[14] = "WideCharToMultiByte"; names[15] = "LocalFree";
            names[16] = "MultiByteToWideChar";
            int kernelLookup = 64;
            int shellLookup = kernelLookup + 17 * 8;
            int kernelIat = shellLookup + 2 * 8;
            int shellIat = kernelIat + 17 * 8;
            int cursor = shellIat + 2 * 8;
            int[] nameOffsets = new int[names.Length];
            i = 0;
            while (i < names.Length) {
                nameOffsets[i] = cursor;
                cursor = Align(cursor + 2 + names[i].Length + 1, 2);
                i = i + 1;
            }
            int kernelDll = cursor;
            cursor = cursor + 13; // KERNEL32.dll and NUL
            int shellDll = cursor;
            cursor = cursor + 12; // SHELL32.dll and NUL
            // A legal no-op base relocation block lets the loader choose an
            // image base; generated references themselves are all RIP relative.
            int relocOffset = Align(cursor, 4);
            cursor = relocOffset + 12;
            int importSize = Align(cursor, 0x200);
            int imageLength = importRaw + importSize;
            byte[] image = new byte[imageLength];

            // DOS, COFF, PE32+, and three section headers fit in 512 bytes.
            int pe = 0x80;
            int optional = pe + 24;
            int sections = optional + 0xf0;
            Write16(image, 0, 0x5a4d); Write32(image, 0x3c, pe);
            Write32(image, pe, 0x4550);
            Write16(image, pe + 4, 0x8664); Write16(image, pe + 6, 3);
            Write16(image, pe + 20, 0xf0); Write16(image, pe + 22, 0x22);
            Write16(image, optional, 0x20b);
            Write32(image, optional + 4, textSize);
            Write32(image, optional + 8, dataSize + importSize);
            Write32(image, optional + 16, textRva);
            Write32(image, optional + 20, textRva);
            Write64(image, optional + 24, 0x400000);
            Write32(image, optional + 32, 0x1000);
            Write32(image, optional + 36, 0x200);
            Write16(image, optional + 40, 6);
            Write16(image, optional + 48, 6);
            Write32(image, optional + 56, Align(importRva + cursor, 0x1000));
            Write32(image, optional + 60, 0x200);
            Write16(image, optional + 68, 3); // console subsystem
            Write16(image, optional + 70, 0x160); // high-entropy ASLR, dynamic base, NX
            Write64(image, optional + 72, 0x100000);
            Write64(image, optional + 80, 0x1000);
            Write64(image, optional + 88, 0x100000);
            Write64(image, optional + 96, 0x1000);
            Write32(image, optional + 108, 16);
            Write32(image, optional + 120, importRva);
            Write32(image, optional + 124, 60);
            Write32(image, optional + 152, importRva + relocOffset);
            Write32(image, optional + 156, 12);
            Write32(image, optional + 208, importRva + kernelIat);
            Write32(image, optional + 212, shellIat + 16 - kernelIat);

            WriteAscii(image, sections, ".text");
            Write32(image, sections + 8, code.Length);
            Write32(image, sections + 12, textRva);
            Write32(image, sections + 16, textSize);
            Write32(image, sections + 20, textRaw);
            Write32(image, sections + 36, 0x60000020);
            int dataSection = sections + 40;
            WriteAscii(image, dataSection, ".data");
            Write32(image, dataSection + 8, dataLength);
            Write32(image, dataSection + 12, dataRva);
            Write32(image, dataSection + 16, dataSize);
            Write32(image, dataSection + 20, dataRaw);
            Write32(image, dataSection + 36, -1073741760);
            int importSection = dataSection + 40;
            WriteAscii(image, importSection, ".idata");
            Write32(image, importSection + 8, cursor);
            Write32(image, importSection + 12, importRva);
            Write32(image, importSection + 16, importSize);
            Write32(image, importSection + 20, importRaw);
            Write32(image, importSection + 36, -1073741760);

            // Import descriptors: KERNEL32, SHELL32, terminating zero entry.
            Write32(image, importRaw, importRva + kernelLookup);
            Write32(image, importRaw + 12, importRva + kernelDll);
            Write32(image, importRaw + 16, importRva + kernelIat);
            Write32(image, importRaw + 20, importRva + shellLookup);
            Write32(image, importRaw + 32, importRva + shellDll);
            Write32(image, importRaw + 36, importRva + shellIat);
            WriteAscii(image, importRaw + kernelDll, "KERNEL32.dll");
            WriteAscii(image, importRaw + shellDll, "SHELL32.dll");
            Write32(image, importRaw + relocOffset, textRva);
            Write32(image, importRaw + relocOffset + 4, 12);

            int kernelIndex = 0;
            i = 0;
            while (i < names.Length) {
                int slot = shellIat;
                if (i != 13) {
                    slot = kernelIat + kernelIndex * 8;
                    Write64(image, importRaw + kernelLookup + kernelIndex * 8,
                            importRva + nameOffsets[i]);
                    kernelIndex = kernelIndex + 1;
                } else {
                    Write64(image, importRaw + shellLookup, importRva + nameOffsets[i]);
                }
                Write64(image, importRaw + slot, importRva + nameOffsets[i]);
                WriteAscii(image, importRaw + nameOffsets[i] + 2, names[i]);
                int thunk = runtime.Offset("win_" + names[i]);
                if (thunk < 0 || runtimeStart + thunk + 6 > code.Length) { return null; }
                Write32(code, runtimeStart + thunk + 2,
                        importRva + slot - (textRva + runtimeStart + thunk + 6));
                i = i + 1;
            }

            i = 0;
            while (i < patchOffsets.Length) {
                if (payloadIndexes[i] < 0 || payloadIndexes[i] >= payloadOffsets.Length) { return null; }
                int patch = patchOffsets[i];
                Write32(code, patch, dataRva + payloadOffsets[payloadIndexes[i]] -
                        (textRva + patch + 4));
                i = i + 1;
            }
            i = 0;
            while (i < code.Length) { image[textRaw + i] = code[i]; i = i + 1; }
            ElfImageBuilder ascii = new ElfImageBuilder();
            i = 0;
            while (i < payloads.Length) {
                int at = dataRaw + payloadOffsets[i];
                Write64(image, at, payloads[i].Length);
                int ch = 0;
                while (ch < payloads[i].Length) {
                    image[at + 8 + ch] = (byte)ascii.AsciiCode(payloads[i][ch]);
                    ch = ch + 1;
                }
                i = i + 1;
            }
            return image;
        }

        private int Align(int value, int unit) {
            return (value + unit - 1) / unit * unit;
        }

        private void WriteAscii(byte[] image,
                                int offset,
                                string value) {
            ElfImageBuilder ascii = new ElfImageBuilder();

            int i = 0;
            while (i < value.Length) {
                image[offset + i] =
                    (byte)ascii.AsciiCode(value[i]);
                i = i + 1;
            }
        }

        private void Write16(byte[] image,
                             int offset,
                             int value) {
            WriteByte(image, offset, value % 256);
            WriteByte(image, offset + 1,
                      (value / 256) % 256);
        }

        private void Write32(byte[] image,
                             int offset,
                             int value) {
            int current = value;
            int i = 0;

            while (i < 4) {
                int part = current % 256;
                if (part < 0) {
                    part = part + 256;
                }

                WriteByte(image, offset + i, part);
                current = (current - part) / 256;
                i = i + 1;
            }
        }

        private void Write64(byte[] image,
                             int offset,
                             int value) {
            Write32(image, offset, value);
            Write32(image, offset + 4, 0);
        }

        private void WriteByte(byte[] image,
                               int offset,
                               int value) {
            image[offset] = (byte)value;
        }
    }
}
