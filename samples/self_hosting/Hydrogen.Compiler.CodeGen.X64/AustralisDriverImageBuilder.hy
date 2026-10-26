using Hydrogen.Compiler.Binding;
using Hydrogen.Compiler.IR;

namespace Hydrogen.Compiler.CodeGen.X64 {
    // AUDR v1: a checked header followed by position-independent kernel code.
    // The entry is static int DriverMain.Run(long context), at code offset zero.
    public class AustralisDriverImageBuilder {
        public byte[] Build(BoundProgram program) {
            if (program == null) { return null; }
            IrModule module = new IrLowering().Lower(program);
            DirectImageResult compiled = new DirectMainCompiler().CompileFreestanding(
                module, "DriverMain", "Run");
            if (!compiled.Success()) { return null; }
            byte[] code = compiled.Image();
            if (code == null || code.Length < 1 || code.Length > 65536) { return null; }

            byte[] image = new byte[24 + code.Length];
            image[0] = (byte)65; image[1] = (byte)85;
            image[2] = (byte)68; image[3] = (byte)82; // AUDR
            image[4] = (byte)1; // format version
            image[5] = (byte)1; // kernel entry ABI
            // Flags and entry offset are zero in v1.
            Write32(image, 8, code.Length);
            Write32(image, 16, Crc32(code));
            int i = 0;
            while (i < code.Length) {
                image[24 + i] = code[i];
                i = i + 1;
            }
            return image;
        }

        private void Write32(byte[] bytes, int offset, long value) {
            int i = 0;
            while (i < 4) {
                bytes[offset + i] = (byte)(value % 256);
                value = value / 256;
                i = i + 1;
            }
        }

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

        private long Crc32(byte[] bytes) {
            long allOnes = 4294967295;
            long polynomial = 3988292384;
            long crc = allOnes;
            int i = 0;
            while (i < bytes.Length) {
                crc = Xor32(crc, (long)bytes[i]);
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
