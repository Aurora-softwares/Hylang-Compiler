using Hydrogen.Compiler.IR;

namespace Hydrogen.Compiler.CodeGen.X64 {
    public class WindowsImageBuilder {
        // Minimal Windows x86-64 PE32+ console executable.
        //
        // One .text section and one .idata section.
        // Imports ExitProcess from KERNEL32.dll.
        //
        // No external assembler, linker or Windows SDK required.
        //
        // First milestone only: this does not yet compile an
        // arbitrary Hydrogen program.


        public byte[] Build(IrModule module) {
            if (module == null || module.Root() == null) {
                return null;
            }

            IrClass[] classes = module.Root().Classes();
            IrMethod mainMethod = null;

            // Find the program entry point.
            int c = 0;
            while (c < classes.Length) {
                IrMethod[] methods = classes[c].Methods();

                int m = 0;
                while (m < methods.Length) {
                    IrMethod method = methods[m];

                    if (method.IsStatic() && method.Name() == "Main") {
                        if (mainMethod != null) {
                            return null;
                        }

                        mainMethod = method;
                    }

                    m = m + 1;
                }

                c = c + 1;
            }

            if (mainMethod == null) {
                return null;
            }

            // Initial experimental subset:
            // static int Main()
            // static int Main(string[] args)
            if (mainMethod.ReturnType() == null ||
                mainMethod.ReturnType().DisplayName() != "int") {
                return null;
            }

            IrParameter[] parameters = mainMethod.Parameters();

            if (parameters.Length > 1) {
                return null;
            }

            if (parameters.Length == 1) {
                if (parameters[0].Type().DisplayName() != "string[]") {
                    return null;
                }
            }

            IrStatement body = mainMethod.Body();

            if (body == null || body.Kind() != IrStatement.KindBlock()) {
                return null;
            }

            IrStatement[] statements = body.Statements();

            // Only a single integer-literal return is supported
            // in the initial Windows target.
            if (statements.Length != 1) {
                return null;
            }

            IrStatement statement = statements[0];

            if (statement == null ||
                statement.Kind() != IrStatement.KindReturnStatement()) {
                return null;
            }

            IrExpression expression = statement.Expression();

            if (expression == null ||
                expression.Kind() != IrExpression.KindLiteral() ||
                expression.LiteralKind() != "number") {
                return null;
            }

            // Parse a non-negative decimal int literal.
            string digits = expression.LiteralText();
            if (digits.Length == 0) {
                return null;
            }

            ElfImageBuilder ascii = new ElfImageBuilder();
            int exitCode = 0;
            int i = 0;

            while (i < digits.Length) {
                int character = ascii.AsciiCode(digits[i]);

                if (character < 48 || character > 57) {
                    return null;
                }

                int digit = character - 48;

                // Prevent signed 32-bit overflow.
                if (exitCode > 214748364) {
                    return null;
                }

                if (exitCode == 214748364 && digit > 7) {
                    return null;
                }

                exitCode = exitCode * 10 + digit;
                i = i + 1;
            }

            // Emit the Windows PE32+ executable.
            return BuildExit(exitCode);
        }


        public byte[] BuildExit(int exitCode) {
            int imageLength = 0x600;
            byte[] image = new byte[imageLength];

            int pe = 0x80;
            int optional = pe + 24;
            int sections = optional + 0xf0;

            int textRva = 0x1000;
            int textRaw = 0x200;
            int importRva = 0x2000;
            int importRaw = 0x400;

            // DOS header and PE header pointer.
            Write16(image, 0x00, 0x5a4d);
            Write32(image, 0x3c, pe);

            // PE signature: "PE\0\0"
            Write32(image, pe, 0x00004550);

            // COFF file header.
            Write16(image, pe + 4, 0x8664); // AMD64
            Write16(image, pe + 6, 2);      // 2 sections
            Write32(image, pe + 8, 0);
            Write32(image, pe + 12, 0);
            Write32(image, pe + 16, 0);
            Write16(image, pe + 20, 0xf0);
            Write16(image, pe + 22, 0x0022);

            // PE32+ optional header.
            Write16(image, optional + 0, 0x20b);
            Write32(image, optional + 4, 0x200);
            Write32(image, optional + 8, 0x200);

            Write32(image, optional + 16, textRva);
            Write32(image, optional + 20, textRva);

            // Preferred base: 0x0000000000400000.
            Write64(image, optional + 24, 0x400000);

            Write32(image, optional + 32, 0x1000);
            Write32(image, optional + 36, 0x200);

            Write16(image, optional + 40, 6);
            Write16(image, optional + 42, 0);

            Write16(image, optional + 48, 6);
            Write16(image, optional + 50, 0);

            Write32(image, optional + 56, 0x3000);
            Write32(image, optional + 60, 0x200);

            Write16(image, optional + 68, 3); // Console
            Write16(image, optional + 70, 0);

            Write64(image, optional + 72, 0x100000);
            Write64(image, optional + 80, 0x1000);
            Write64(image, optional + 88, 0x100000);
            Write64(image, optional + 96, 0x1000);

            Write32(image, optional + 108, 16);

            // Import data directory.
            Write32(image, optional + 120, importRva);
            Write32(image, optional + 124, 40);

            // .text section.
            WriteAscii(image, sections, ".text");
            Write32(image, sections + 8, 14);
            Write32(image, sections + 12, textRva);
            Write32(image, sections + 16, 0x200);
            Write32(image, sections + 20, textRaw);
            Write32(image, sections + 36, 0x60000020);

            // .idata section.
            int idataSection = sections + 40;
            WriteAscii(image, idataSection, ".idata");
            Write32(image, idataSection + 8, 0x100);
            Write32(image, idataSection + 12, importRva);
            Write32(image, idataSection + 16, 0x200);
            Write32(image, idataSection + 20, importRaw);
            Write32(image, idataSection + 36, -1073741760);

            // Windows x64 entry point:
            //
            // sub rsp, 40          ; 32-byte shadow space
            // mov ecx, exitCode   ; first Windows argument
            // call [rip + disp32] ; imported ExitProcess
            // ud2                  ; unreachable
            //
            X64Assembler code = new X64Assembler();

            code.EmitByte(0x48);
            code.EmitByte(0x83);
            code.EmitByte(0xec);
            code.EmitByte(0x28);

            code.EmitByte(0xb9);
            code.Emit32(exitCode);

            code.EmitByte(0xff);
            code.EmitByte(0x15);

            // RIP at the end of call = 0x100F.
            // IAT RVA = 0x2038.
            code.Emit32(0x2038 - 0x100f);

            code.EmitByte(0x0f);
            code.EmitByte(0x0b);

            byte[] machineCode = code.ToArray();
            int i = 0;
            while (i < machineCode.Length) {
                image[textRaw + i] = machineCode[i];
                i = i + 1;
            }

            // Import descriptor at RVA 0x2000.
            // Import lookup table at RVA 0x2028.
            // Import address table at RVA 0x2038.
            // Hint/name at RVA 0x2048.
            // DLL name at RVA 0x2058.
            //
            // The second descriptor and the second
            // entry of each thunk array remain zero.

            Write32(image, importRaw + 0x00, 0x2028);
            Write32(image, importRaw + 0x0c, 0x2058);
            Write32(image, importRaw + 0x10, 0x2038);

            Write64(image, importRaw + 0x28, 0x2048);
            Write64(image, importRaw + 0x38, 0x2048);

            Write16(image, importRaw + 0x48, 0);
            WriteAscii(image, importRaw + 0x4a, "ExitProcess");
            WriteAscii(image, importRaw + 0x58, "KERNEL32.dll");

            return image;
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
