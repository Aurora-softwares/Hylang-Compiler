using Hydrogen.Compiler.Binding;

namespace Hydrogen.Compiler.CodeGen.X64 {
    // Minimal Australis Exec v1 backend: one WriteLine("ASCII literal") then exit.
    public class AustralisExecImageBuilder {
        public byte[] Build(BoundProgram program) {
            if (program == null) { return null; }
            BoundOp[] ops = program.EntryOps();
            if (ops.Length != 2 ||
                ops[0].Kind() != BoundOp.KindWriteLineLiteral() ||
                ops[1].Kind() != BoundOp.KindExit()) { return null; }
            if (ops[1].ExitCode() < 0 || ops[1].ExitCode() > 255) { return null; }

            string message = ops[0].Text();
            ElfImageBuilder ascii = new ElfImageBuilder();
            if (!ascii.SupportsPayload(message)) { return null; }
            int dataLength = message.Length + 2; // CRLF
            if (dataLength > 65536) { return null; }

            // 32-byte header + 11-byte WRITE/EXIT program + initialized data.
            int codeLength = 11;
            int dataOffset = 32 + codeLength;
            byte[] output = new byte[dataOffset + dataLength];

            // Australis Exec v1: signature, version, header size, two reserved bytes.
            output[0] = (byte)65; output[1] = (byte)85;
            output[2] = (byte)69; output[3] = (byte)88;
            output[4] = (byte)1; output[5] = (byte)32;
            Write32(output, 8, codeLength);
            Write32(output, 12, dataLength);
            Write32(output, 16, dataLength); // total writable data capacity
            Write32(output, 20, 0);          // entrypoint at code offset zero

            output[32] = (byte)2;             // WRITE opcode
            Write32(output, 33, 5242880);   // data virtual base: 0x500000
            Write32(output, 37, dataLength);
            output[41] = (byte)1;             // EXIT opcode
            output[42] = (byte)ops[1].ExitCode();

            int i = 0;
            while (i < message.Length) {
                output[dataOffset + i] = (byte)ascii.AsciiCode(message[i]);
                i = i + 1;
            }
            output[dataOffset + message.Length] = (byte)13;
            output[dataOffset + message.Length + 1] = (byte)10;

            Write32(output, 24, Crc32(output, 32, codeLength));
            Write32(output, 28, Crc32(output, dataOffset, dataLength));
            return output;
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

        // CRC-32/ISO-HDLC (same algorithm as Python zlib.crc32).
        private long Crc32(byte[] data, int offset, int count) {
            // Build unsigned 32-bit constants from smaller literals because
            // the current native backend parses numeric literals as int.
            long allOnes = 65535;
            allOnes = allOnes * 65536 + 65535;
            long polynomial = 39882;
            polynomial = polynomial * 100000 + 92384;
            long crc = allOnes;
            int i = 0;
            while (i < count) {
                crc = Xor32(crc, (long)data[offset + i]);
                int b = 0;
                while (b < 8) {
                    if (crc % 2 == 1) {
                        crc = Xor32(crc / 2, polynomial);
                    } else {
                        crc = crc / 2;
                    }
                    b = b + 1;
                }
                i = i + 1;
            }
            return Xor32(crc, allOnes);
        }
    }
}
