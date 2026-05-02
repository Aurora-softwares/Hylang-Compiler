using Hydrogen.Compiler.IR;

namespace Hydrogen.Compiler.CodeGen.X64 {
    public class ElfImageBuilder {
        public byte[] BuildText(string text, int exitCode) {
            return BuildSysWriteExit(text, exitCode);
        }

        public byte[] BuildWriteLineProgram(IrProgram program) {
            string text = program.Message() + "\n";
            return BuildSysWriteExit(text, program.ExitCode());
        }

        public byte[] BuildIrModuleDebug(IrModule module) {
            return BuildSysWriteExit(module.ToDebugText(), 0);
        }

        public byte[] BuildEntryPoint(IrEntryPoint entryPoint) {
            // Emit a write syscall for each WriteLine literal, then exit(exitCode).
            IrOp[] ops = entryPoint.Ops();

            // Gather payloads and final exit code.
            string[] payloads = new string[0];
            int payloadCount = 0;
            int exitCode = 0;
            int i = 0;
            while (i < ops.Length) {
                if (ops[i].Kind() == IrOp.KindWriteLineLiteral()) {
                    payloads = AppendString(payloads, payloadCount, ops[i].Text() + "\n");
                    payloadCount = payloadCount + 1;
                } else if (ops[i].Kind() == IrOp.KindExit()) {
                    exitCode = ops[i].ExitCode();
                }
                i = i + 1;
            }

            int headerSize = 64 + 56;
            X64Assembler code = new X64Assembler();

            int[] leaSites = new int[0];
            int leaCount = 0;
            int[] payloadIndexByLea = new int[0];
            int payloadIndexCount = 0;

            int p = 0;
            while (p < payloadCount) {
                // mov rax, 1
                code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc0); code.Emit32(1);
                // mov rdi, 1
                code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc7); code.Emit32(1);
                // lea rsi, [rip+disp32] (patch later)
                int leaStart = code.Position();
                code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x35); code.Emit32(0);
                leaSites = AppendInt(leaSites, leaCount, leaStart);
                leaCount = leaCount + 1;
                payloadIndexByLea = AppendInt(payloadIndexByLea, payloadIndexCount, p);
                payloadIndexCount = payloadIndexCount + 1;
                // mov rdx, len
                code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc2); code.Emit32(payloads[p].Length);
                // syscall
                code.EmitByte(0x0f); code.EmitByte(0x05);
                p = p + 1;
            }

            // exit(exitCode)
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc0); code.Emit32(60);
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc7); code.Emit32(exitCode);
            code.EmitByte(0x0f); code.EmitByte(0x05);

            byte[] codeBytes = code.ToArray();
            int codeOffset = headerSize;

            // rodata starts after code
            int rodataOffset = codeOffset + codeBytes.Length;
            int[] payloadOffsets = new int[payloadCount];
            int roCursor = rodataOffset;
            int pi = 0;
            while (pi < payloadCount) {
                payloadOffsets[pi] = roCursor;
                roCursor = roCursor + payloads[pi].Length;
                pi = pi + 1;
            }
            int totalSize = roCursor;

            // Patch each lea to point at its payload
            int l = 0;
            while (l < leaCount) {
                int leaStart = leaSites[l];
                int payloadIndex = payloadIndexByLea[l];
                int target = payloadOffsets[payloadIndex];
                int nextIp = codeOffset + leaStart + 7;
                int disp = target - nextIp;
                WriteDisp32(codeBytes, leaStart + 3, disp);
                l = l + 1;
            }

            byte[] image = new byte[totalSize];
            WriteElfHeader(image, codeOffset);
            WriteProgramHeader(image, totalSize);

            int ci = 0;
            while (ci < codeBytes.Length) {
                image[codeOffset + ci] = codeBytes[ci];
                ci = ci + 1;
            }

            int dataCursor = rodataOffset;
            int di = 0;
            while (di < payloadCount) {
                string payload = payloads[di];
                int k = 0;
                while (k < payload.Length) {
                    image[dataCursor + k] = (byte)AsciiCode(payload[k]);
                    k = k + 1;
                }
                dataCursor = dataCursor + payload.Length;
                di = di + 1;
            }

            return image;
        }

        private void WriteDisp32(byte[] bytes, int offset, int value) {
            int temp = value;
            bytes[offset + 0] = (byte)Mod256(temp);
            temp = temp / 256;
            bytes[offset + 1] = (byte)Mod256(temp);
            temp = temp / 256;
            bytes[offset + 2] = (byte)Mod256(temp);
            temp = temp / 256;
            bytes[offset + 3] = (byte)Mod256(temp);
        }

        private int Mod256(int value) {
            int result = value % 256;
            if (result < 0) {
                result = result + 256;
            }
            return result;
        }

        private byte[] BuildSysWriteExit(string text, int exitCode) {
            string payload = text;
            if (payload.Length == 0 || payload[payload.Length - 1] != "\n") {
                payload = payload + "\n";
            }

            // ELF layout: [hdr64=64][phdr=56][padding...][code][rodata]
            int headerSize = 64 + 56;
            X64Assembler code = new X64Assembler();

            // Linux syscall ABI:
            // write(1, rip+disp32, len); exit(exitCode)
            //
            // mov rax, 1
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc0); code.Emit32(1);
            // mov rdi, 1
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc7); code.Emit32(1);
            // lea rsi, [rip+disp32]  (disp patched later)
            int leaOffset = code.Position();
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x35); code.Emit32(0);
            // mov rdx, len
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc2); code.Emit32(payload.Length);
            // syscall
            code.EmitByte(0x0f); code.EmitByte(0x05);
            // mov rax, 60
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc0); code.Emit32(60);
            // mov rdi, exitCode
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0xc7); code.Emit32(exitCode);
            // syscall
            code.EmitByte(0x0f); code.EmitByte(0x05);

            byte[] codeBytes = code.ToArray();
            int codeOffset = headerSize;
            int rodataOffset = codeOffset + codeBytes.Length;
            int totalSize = rodataOffset + payload.Length;

            // Patch RIP-relative displacement: target = rodataOffset, nextIP = leaEnd
            int leaInstrStart = leaOffset;
            int nextIp = codeOffset + leaInstrStart + 7;
            int disp = rodataOffset - nextIp;
            WriteDisp32(codeBytes, leaInstrStart + 3, disp);

            byte[] image = new byte[totalSize];
            WriteElfHeader(image, codeOffset);
            WriteProgramHeader(image, totalSize);

            int i = 0;
            while (i < codeBytes.Length) {
                image[codeOffset + i] = codeBytes[i];
                i = i + 1;
            }

            int j = 0;
            while (j < payload.Length) {
                image[rodataOffset + j] = (byte)AsciiCode(payload[j]);
                j = j + 1;
            }

            return image;
        }

        private void WriteElfHeader(byte[] image, int codeOffset) {
            SetByte(image, 0, 0x7f);
            SetByte(image, 1, 0x45);
            SetByte(image, 2, 0x4c);
            SetByte(image, 3, 0x46);
            SetByte(image, 4, 2);
            SetByte(image, 5, 1);
            SetByte(image, 6, 1);

            Write16(image, 16, 2);
            Write16(image, 18, 0x3e);
            Write32(image, 20, 1);
            Write64(image, 24, 0x400000 + codeOffset);
            Write64(image, 32, 64);
            Write64(image, 40, 0);
            Write32(image, 48, 0);
            Write16(image, 52, 64);
            Write16(image, 54, 56);
            Write16(image, 56, 1);
            Write16(image, 58, 0);
            Write16(image, 60, 0);
            Write16(image, 62, 0);
        }

        private void WriteProgramHeader(byte[] image, int totalSize) {
            Write32(image, 64, 1);
            Write32(image, 68, 5);
            Write64(image, 72, 0);
            Write64(image, 80, 0x400000);
            Write64(image, 88, 0x400000);
            Write64(image, 96, totalSize);
            Write64(image, 104, totalSize);
            Write64(image, 112, 0x1000);
        }

        private string[] AppendString(string[] items, int count, string item) {
            string[] next = new string[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private int[] AppendInt(int[] items, int count, int item) {
            int[] next = new int[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private void SetByte(byte[] image, int offset, int value) {
            image[offset] = (byte)value;
        }

        private void Write16(byte[] image, int offset, int value) {
            SetByte(image, offset, value % 256);
            SetByte(image, offset + 1, (value / 256) % 256);
        }

        private void Write32(byte[] image, int offset, int value) {
            SetByte(image, offset, value % 256);
            SetByte(image, offset + 1, (value / 256) % 256);
            SetByte(image, offset + 2, (value / 65536) % 256);
            SetByte(image, offset + 3, (value / 16777216) % 256);
        }

        private void Write64(byte[] image, int offset, int value) {
            Write32(image, offset, value);
            Write32(image, offset + 4, 0);
        }

        private int AsciiCode(string ch) {
            if (ch == "\n") { return 10; }
            if (ch == " ") { return 32; }
            if (ch == "!") { return 33; }
            if (ch == "\"") { return 34; }
            if (ch == "#") { return 35; }
            if (ch == "$") { return 36; }
            if (ch == "%") { return 37; }
            if (ch == "&") { return 38; }
            if (ch == "'") { return 39; }
            if (ch == "(") { return 40; }
            if (ch == ")") { return 41; }
            if (ch == "*") { return 42; }
            if (ch == "+") { return 43; }
            if (ch == ",") { return 44; }
            if (ch == "-") { return 45; }
            if (ch == ".") { return 46; }
            if (ch == "/") { return 47; }
            if (ch == "0") { return 48; }
            if (ch == "1") { return 49; }
            if (ch == "2") { return 50; }
            if (ch == "3") { return 51; }
            if (ch == "4") { return 52; }
            if (ch == "5") { return 53; }
            if (ch == "6") { return 54; }
            if (ch == "7") { return 55; }
            if (ch == "8") { return 56; }
            if (ch == "9") { return 57; }
            if (ch == ":") { return 58; }
            if (ch == ";") { return 59; }
            if (ch == "<") { return 60; }
            if (ch == "=") { return 61; }
            if (ch == ">") { return 62; }
            if (ch == "?") { return 63; }
            if (ch == "@") { return 64; }
            if (ch == "A") { return 65; }
            if (ch == "B") { return 66; }
            if (ch == "C") { return 67; }
            if (ch == "D") { return 68; }
            if (ch == "E") { return 69; }
            if (ch == "F") { return 70; }
            if (ch == "G") { return 71; }
            if (ch == "H") { return 72; }
            if (ch == "I") { return 73; }
            if (ch == "J") { return 74; }
            if (ch == "K") { return 75; }
            if (ch == "L") { return 76; }
            if (ch == "M") { return 77; }
            if (ch == "N") { return 78; }
            if (ch == "O") { return 79; }
            if (ch == "P") { return 80; }
            if (ch == "Q") { return 81; }
            if (ch == "R") { return 82; }
            if (ch == "S") { return 83; }
            if (ch == "T") { return 84; }
            if (ch == "U") { return 85; }
            if (ch == "V") { return 86; }
            if (ch == "W") { return 87; }
            if (ch == "X") { return 88; }
            if (ch == "Y") { return 89; }
            if (ch == "Z") { return 90; }
            if (ch == "[") { return 91; }
            if (ch == "\\") { return 92; }
            if (ch == "]") { return 93; }
            if (ch == "^") { return 94; }
            if (ch == "_") { return 95; }
            if (ch == "`") { return 96; }
            if (ch == "a") { return 97; }
            if (ch == "b") { return 98; }
            if (ch == "c") { return 99; }
            if (ch == "d") { return 100; }
            if (ch == "e") { return 101; }
            if (ch == "f") { return 102; }
            if (ch == "g") { return 103; }
            if (ch == "h") { return 104; }
            if (ch == "i") { return 105; }
            if (ch == "j") { return 106; }
            if (ch == "k") { return 107; }
            if (ch == "l") { return 108; }
            if (ch == "m") { return 109; }
            if (ch == "n") { return 110; }
            if (ch == "o") { return 111; }
            if (ch == "p") { return 112; }
            if (ch == "q") { return 113; }
            if (ch == "r") { return 114; }
            if (ch == "s") { return 115; }
            if (ch == "t") { return 116; }
            if (ch == "u") { return 117; }
            if (ch == "v") { return 118; }
            if (ch == "w") { return 119; }
            if (ch == "x") { return 120; }
            if (ch == "y") { return 121; }
            if (ch == "z") { return 122; }
            if (ch == "{") { return 123; }
            if (ch == "|") { return 124; }
            if (ch == "}") { return 125; }
            if (ch == "~") { return 126; }
            return 63;
        }
    }
}
