using Hydrogen.Compiler.Binding;
using Hydrogen.Compiler.Core;
using Hydrogen.Compiler.IR;

namespace Hydrogen.Compiler.CodeGen.X64 {
    // AUDR v1 and v2: a checked header followed by position-independent code.
    // The entry remains static int DriverMain.Run(long context), at code offset zero.
    public class AustralisDriverImageBuilder {
        public byte[] Build(BoundProgram program, HyprojManifest manifest) {
            if (program == null || manifest == null || !manifest.ValidDriver()) { return null; }
            bool v2 = manifest.DriverAbi() == 2;
            IrModule module = new IrLowering().Lower(program);
            DirectImageResult compiled = new DirectMainCompiler().CompileFreestanding(
                module, "DriverMain", "Run");
            if (!compiled.Success()) { return null; }
            byte[] body = compiled.Image();
            int maximumBody = 65525;
            if (v2) { maximumBody = 1048565; }
            if (body == null || body.Length < 1 || body.Length > maximumBody) { return null; }
            // CallKernel passes context in rdi. Freestanding Hydrogen methods
            // read their first argument at [rbp+16], so use a tiny entry shim
            // without changing the ABI of existing native runtime callers.
            byte[] code = new byte[11 + body.Length];
            code[0] = (byte)87; // push rdi
            code[1] = (byte)232; // call +5, to compiled body at byte 11
            code[2] = (byte)5;
            code[6] = (byte)72; code[7] = (byte)131;
            code[8] = (byte)196; code[9] = (byte)8; // add rsp, 8
            code[10] = (byte)195; // ret
            int bodyIndex = 0;
            while (bodyIndex < body.Length) {
                code[11 + bodyIndex] = body[bodyIndex];
                bodyIndex = bodyIndex + 1;
            }

            int headerLength = 24;
            if (v2) { headerLength = 48; }
            byte[] image = new byte[headerLength + code.Length];
            image[0] = (byte)65; image[1] = (byte)85;
            image[2] = (byte)68; image[3] = (byte)82; // AUDR
            image[4] = (byte)manifest.DriverAbi();
            image[5] = (byte)manifest.DriverAbi();
            // Flags and entry offset are zero in both versions.
            Write32(image, 8, code.Length);
            if (v2) {
                Write32(image, 24, manifest.DriverMatchKind());
                Write32(image, 28, manifest.DriverVendor());
                Write32(image, 32, manifest.DriverDevice());
                Write32(image, 36, manifest.DriverClass());
                Write32(image, 40, manifest.DriverSubclass());
                Write32(image, 44, manifest.DriverInterface());
            }
            int i = 0;
            while (i < code.Length) {
                image[headerLength + i] = code[i];
                i = i + 1;
            }
            Write32(image, 16, Crc32(image, 24, image.Length - 24));
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

        private long Crc32(byte[] bytes, int offset, int length) {
            long allOnes = 65535; allOnes = allOnes * 65536 + 65535;
            long polynomial = 39882; polynomial = polynomial * 100000 + 92384;
            long crc = allOnes;
            int i = 0;
            while (i < length) {
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
