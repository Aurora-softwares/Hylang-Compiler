using Hydrogen.Compiler.Binding;

namespace Hydrogen.Compiler.CodeGen.X64 {
    // Emits checked AUEX v1 bytecode for the Australis user runtime. Literal
    // data is packed into the initialized data segment and terminal/file
    // reads share a compiler allocated scratch region after those literals.
    public class AustralisExecImageBuilder {
        private static long DataBase() { return 5242880; }

        public byte[] Build(BoundProgram program) {
            if (program == null) { return null; }
            BoundOp[] ops = program.EntryOps();
            if (ops.Length == 0 || ops[ops.Length - 1].Kind() != BoundOp.KindExit()) {
                return null;
            }

            ElfImageBuilder ascii = new ElfImageBuilder();
            int codeLength = 0;
            int dataLength = 0;
            int scratchCapacity = 0;
            int i = 0;
            while (i < ops.Length) {
                BoundOp op = ops[i];
                int kind = op.Kind();
                if (kind == BoundOp.KindWriteLineLiteral()) {
                    if (!ascii.SupportsPayload(op.Text())) { return null; }
                    codeLength = codeLength + 9;
                    dataLength = dataLength + op.Text().Length + 2;
                } else if (kind == BoundOp.KindUserWriteLiteral()) {
                    if (!ascii.SupportsPayload(op.Text())) { return null; }
                    codeLength = codeLength + 9;
                    dataLength = dataLength + op.Text().Length;
                } else if (kind == BoundOp.KindUserReadTerminal() ||
                    kind == BoundOp.KindUserReadFile()) {
                    int capacity = op.ExitCode();
                    if (capacity < 1 || capacity > 65536) { return null; }
                    if (capacity > scratchCapacity) { scratchCapacity = capacity; }
                    codeLength = codeLength + 9;
                } else if (kind == BoundOp.KindUserWriteResult()) {
                    codeLength = codeLength + 5;
                } else if (kind == BoundOp.KindUserOpenLiteral()) {
                    if (op.Text().Length < 1 || op.Text().Length > 255 ||
                        !ascii.SupportsPayload(op.Text())) { return null; }
                    codeLength = codeLength + 9;
                    dataLength = dataLength + op.Text().Length;
                } else if (kind == BoundOp.KindUserCloseFile() ||
                    kind == BoundOp.KindUserYield()) {
                    codeLength = codeLength + 1;
                } else if (kind == BoundOp.KindUserStoreByte()) {
                    if (op.Argument() < 0 || op.ExitCode() < 0 ||
                        op.ExitCode() > 255) { return null; }
                    codeLength = codeLength + 6;
                } else if (kind == BoundOp.KindExit()) {
                    if (i != ops.Length - 1 || op.ExitCode() < 0 || op.ExitCode() > 255) {
                        return null;
                    }
                    codeLength = codeLength + 2;
                } else {
                    return null;
                }
                if (codeLength > 65536 || dataLength > 65536) { return null; }
                i = i + 1;
            }
            if (scratchCapacity > 65536 - dataLength) { return null; }

            int dataCapacity = dataLength + scratchCapacity;
            int dataOffset = 32 + codeLength;
            byte[] output = new byte[dataOffset + dataLength];
            output[0] = (byte)65; output[1] = (byte)85;
            output[2] = (byte)69; output[3] = (byte)88;
            output[4] = (byte)1; output[5] = (byte)32;
            Write32(output, 8, codeLength);
            Write32(output, 12, dataLength);
            Write32(output, 16, dataCapacity);
            Write32(output, 20, 0);

            int code = 32;
            int data = 0;
            long scratchAddress = DataBase() + dataLength;
            i = 0;
            while (i < ops.Length) {
                BoundOp op2 = ops[i];
                int kind2 = op2.Kind();
                if (kind2 == BoundOp.KindWriteLineLiteral() ||
                    kind2 == BoundOp.KindUserWriteLiteral()) {
                    int count = op2.Text().Length;
                    if (kind2 == BoundOp.KindWriteLineLiteral()) { count = count + 2; }
                    output[code] = (byte)2;
                    Write32(output, code + 1, DataBase() + data);
                    Write32(output, code + 5, count);
                    CopyAscii(output, dataOffset + data, op2.Text(), ascii);
                    data = data + op2.Text().Length;
                    if (kind2 == BoundOp.KindWriteLineLiteral()) {
                        output[dataOffset + data] = (byte)13;
                        output[dataOffset + data + 1] = (byte)10;
                        data = data + 2;
                    }
                    code = code + 9;
                } else if (kind2 == BoundOp.KindUserReadTerminal()) {
                    output[code] = (byte)3;
                    Write32(output, code + 1, scratchAddress);
                    Write32(output, code + 5, op2.ExitCode());
                    code = code + 9;
                } else if (kind2 == BoundOp.KindUserWriteResult()) {
                    output[code] = (byte)4;
                    Write32(output, code + 1, scratchAddress);
                    code = code + 5;
                } else if (kind2 == BoundOp.KindUserOpenLiteral()) {
                    output[code] = (byte)5;
                    Write32(output, code + 1, DataBase() + data);
                    Write32(output, code + 5, op2.Text().Length);
                    CopyAscii(output, dataOffset + data, op2.Text(), ascii);
                    data = data + op2.Text().Length;
                    code = code + 9;
                } else if (kind2 == BoundOp.KindUserReadFile()) {
                    output[code] = (byte)6;
                    Write32(output, code + 1, scratchAddress);
                    Write32(output, code + 5, op2.ExitCode());
                    code = code + 9;
                } else if (kind2 == BoundOp.KindUserCloseFile()) {
                    output[code] = (byte)7; code = code + 1;
                } else if (kind2 == BoundOp.KindUserStoreByte()) {
                    output[code] = (byte)8;
                    Write32(output, code + 1, op2.Argument());
                    output[code + 5] = (byte)op2.ExitCode();
                    code = code + 6;
                } else if (kind2 == BoundOp.KindUserYield()) {
                    output[code] = (byte)9; code = code + 1;
                } else if (kind2 == BoundOp.KindExit()) {
                    output[code] = (byte)1;
                    output[code + 1] = (byte)op2.ExitCode();
                    code = code + 2;
                }
                i = i + 1;
            }

            Write32(output, 24, Crc32(output, 32, codeLength));
            Write32(output, 28, Crc32(output, dataOffset, dataLength));
            return output;
        }

        private void CopyAscii(byte[] output, int offset, string value, ElfImageBuilder ascii) {
            int i = 0;
            while (i < value.Length) {
                output[offset + i] = (byte)ascii.AsciiCode(value[i]);
                i = i + 1;
            }
        }

        private void Write32(byte[] output, int offset, long value) {
            int i = 0;
            while (i < 4) {
                output[offset + i] = (byte)(value % 256);
                value = value / 256;
                i = i + 1;
            }
        }

        // Hydrogen currently has no ^ operator. Implement unsigned XOR
        // arithmetically, preserving all 32 bits using a 64-bit long.
        private long Xor32(long left, long right) {
            long result = 0;
            long bit = 1;
            while (left > 0 || right > 0) {
                if (left % 2 != right % 2) { result = result + bit; }
                left = left / 2;
                right = right / 2;
                bit = bit * 2;
            }
            return result;
        }

        private long Crc32(byte[] bytes, int offset, int count) {
            long allOnes = 65535;
            allOnes = allOnes * 65536 + 65535;
            long polynomial = 39882;
            polynomial = polynomial * 100000 + 92384;
            long crc = allOnes;
            int i = 0;
            while (i < count) {
                crc = Xor32(crc, (long)bytes[offset + i]);
                int bit = 0;
                while (bit < 8) {
                    if (crc % 2 == 1) { crc = Xor32(crc / 2, polynomial); }
                    else { crc = crc / 2; }
                    bit = bit + 1;
                }
                i = i + 1;
            }
            return Xor32(crc, allOnes);
        }
    }
}
