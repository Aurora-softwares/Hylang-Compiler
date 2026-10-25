using Hydrogen.Compiler.Binding;

namespace Hydrogen.Compiler.CodeGen.X64 {
    // AUN1 version 2: a 16-byte header and one position-independent code page.
    // This first source profile accepts literal terminal writes and a literal
    // exit status from Main(string[]). Literals live in the readable code page.
    public class AustralisNativeImageBuilder {
        public byte[] Build(BoundProgram program) {
            if (program == null) { return null; }
            BoundOp[] ops = program.EntryOps();
            if (ops == null || ops.Length == 0) { return null; }
            X64Assembler code = new X64Assembler();
            int[] patches = new int[ops.Length];
            string[] literals = new string[ops.Length];
            int literalCount = 0;
            bool exited = false;
            ElfImageBuilder ascii = new ElfImageBuilder();
            int i = 0;
            while (i < ops.Length) {
                BoundOp op = ops[i];
                if (exited) { return null; }
                if (op.Kind() == BoundOp.KindUserWriteLiteral()) {
                    string literal = op.Text();
                    if (literal.Length > 256 || !ascii.SupportsPayload(literal)) { return null; }
                    code.EmitByte(72); code.EmitByte(141); code.EmitByte(61); // lea rdi, [rip+rel32]
                    patches[literalCount] = code.Position(); code.Emit32(0);
                    code.EmitByte(190); code.Emit32(literal.Length); // mov esi, length
                    code.EmitByte(184); code.Emit32(3); // write
                    code.EmitByte(205); code.EmitByte(128); // int 0x80
                    literals[literalCount] = literal;
                    literalCount = literalCount + 1;
                } else if (op.Kind() == BoundOp.KindExit()) {
                    code.EmitByte(191); code.Emit32(op.ExitCode()); // mov edi, exit status
                    code.EmitByte(184); code.Emit32(1); // exit
                    code.EmitByte(205); code.EmitByte(128);
                    code.EmitByte(15); code.EmitByte(11); // ud2 if exit returns
                    exited = true;
                } else {
                    return null;
                }
                i = i + 1;
            }
            if (!exited) { return null; }
            i = 0;
            while (i < literalCount) {
                int offset = code.Position();
                code.Patch32(patches[i], offset - patches[i] - 4);
                int ch = 0;
                while (ch < literals[i].Length) {
                    code.EmitByte(ascii.AsciiCode(literals[i][ch]));
                    ch = ch + 1;
                }
                i = i + 1;
            }
            byte[] body = code.ToArray();
            if (body.Length < 1 || body.Length > 4096) { return null; }
            byte[] image = new byte[16 + body.Length];
            image[0] = (byte)65; image[1] = (byte)85;
            image[2] = (byte)78; image[3] = (byte)49; // AUN1
            image[4] = (byte)(body.Length % 256);
            image[5] = (byte)(body.Length / 256);
            image[6] = (byte)2; // version
            // flags, entry offset, data length and reserved bytes remain zero.
            i = 0;
            while (i < body.Length) { image[16 + i] = body[i]; i = i + 1; }
            return image;
        }
    }
}
