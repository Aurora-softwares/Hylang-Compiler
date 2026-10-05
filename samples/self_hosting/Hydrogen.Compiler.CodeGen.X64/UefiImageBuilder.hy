using Hydrogen.Compiler.IR;

namespace Hydrogen.Compiler.CodeGen.X64 {
    public class UefiImageResult {
        private bool success;
        private byte[] image;
        private string message;

        public UefiImageResult(bool inputSuccess, byte[] inputImage, string inputMessage) {
            success = inputSuccess;
            image = inputImage;
            message = inputMessage;
        }

        public bool Success() { return success; }
        public byte[] Image() { return image; }
        public string Message() { return message; }
    }

    // A freestanding x86_64 UEFI proof target. It deliberately has no Linux
    // runtime: the entry point uses the UEFI Microsoft x64 ABI and invokes
    // EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL.OutputString through its function pointer.
    public class UefiImageBuilder {
        public UefiImageResult Build(IrEntryPoint entryPoint) {
            IrOp[] ops = entryPoint.Ops();
            string payload = "";
            int writes = 0;
            int i = 0;
            while (i < ops.Length) {
                if (ops[i].Kind() == IrOp.KindWriteLineLiteral()) {
                    payload = payload + ops[i].Text() + "\r\n";
                    writes = writes + 1;
                } else if (ops[i].Kind() != IrOp.KindExit()) {
                    return Failed("UEFI target supports only System.Console.WriteLine string literals");
                }
                i = i + 1;
            }
            if (writes == 0) { return Failed("UEFI target requires at least one System.Console.WriteLine string literal"); }

            ElfImageBuilder ascii = new ElfImageBuilder();
            if (!ascii.SupportsPayload(payload)) {
                return Failed("UEFI target currently supports ASCII string literals only");
            }
            // The initial image reserves one 512-byte read-only section.
            if ((payload.Length + 1) * 2 > 512) {
                return Failed("UEFI console payload is too long for the initial target");
            }
            return new UefiImageResult(true, BuildImage(payload, ascii), "");
        }

        private UefiImageResult Failed(string message) {
            return new UefiImageResult(false, new byte[0], message);
        }

        private byte[] BuildImage(string payload, ElfImageBuilder ascii) {
            int headers = 512;
            int textOffset = 512;
            int dataOffset = 1024;
            int textRva = 4096;
            int dataRva = 8192;
            byte[] image = new byte[1536];

            // MS-DOS stub and PE/COFF header.
            image[0] = (byte)77; image[1] = (byte)90;
            Write32(image, 60, 128);
            image[128] = (byte)80; image[129] = (byte)69;
            Write16(image, 132, 34404); // IMAGE_FILE_MACHINE_AMD64
            Write16(image, 134, 2);
            Write16(image, 148, 240);
            Write16(image, 150, 546); // executable, large-address-aware, debug stripped

            int optional = 152;
            Write16(image, optional, 523); // PE32+
            Write32(image, optional + 4, 512);
            Write32(image, optional + 8, 512);
            Write32(image, optional + 16, textRva);
            Write32(image, optional + 20, textRva);
            Write32(image, optional + 24, 1073741824); // image base 0x0000000140000000
            Write32(image, optional + 28, 1);
            Write32(image, optional + 32, 4096);
            Write32(image, optional + 36, 512);
            Write16(image, optional + 48, 2);
            Write32(image, optional + 56, 12288);
            Write32(image, optional + 60, headers);
            Write16(image, optional + 68, 10); // IMAGE_SUBSYSTEM_EFI_APPLICATION
            Write16(image, optional + 70, 256); // NX compatible
            Write64(image, optional + 72, 1048576);
            Write64(image, optional + 80, 4096);
            Write64(image, optional + 88, 1048576);
            Write64(image, optional + 96, 4096);
            Write32(image, optional + 108, 16);

            int section = optional + 240;
            WriteName(image, section, ".text", ascii);
            Write32(image, section + 8, 26);
            Write32(image, section + 12, textRva);
            Write32(image, section + 16, 512);
            Write32(image, section + 20, textOffset);
            Write32(image, section + 36, 1610612768); // code, execute, read

            int dataSection = section + 40;
            WriteName(image, dataSection, ".rdata", ascii);
            Write32(image, dataSection + 8, (payload.Length + 1) * 2);
            Write32(image, dataSection + 12, dataRva);
            Write32(image, dataSection + 16, 512);
            Write32(image, dataSection + 20, dataOffset);
            Write32(image, dataSection + 36, 1073741888); // initialized data, read

            // EFIAPI entry: RDX is EFI_SYSTEM_TABLE*. ConOut is +0x40; its
            // OutputString callback is +8. RCX/RDX are the first two MS x64 args.
            int[] code = new int[26];
            code[0] = 72; code[1] = 131; code[2] = 236; code[3] = 40;
            code[4] = 72; code[5] = 139; code[6] = 66; code[7] = 64;
            code[8] = 72; code[9] = 137; code[10] = 193;
            code[11] = 72; code[12] = 139; code[13] = 64; code[14] = 8;
            code[15] = 72; code[16] = 141; code[17] = 21; code[18] = 234; code[19] = 15; code[20] = 0; code[21] = 0;
            code[22] = 255; code[23] = 208;
            code[24] = 235; code[25] = 254; // retain the message on screen
            int i = 0;
            while (i < code.Length) { image[textOffset + i] = (byte)code[i]; i = i + 1; }

            int cursor = dataOffset;
            i = 0;
            while (i < payload.Length) {
                image[cursor] = (byte)ascii.AsciiCode(payload[i]);
                image[cursor + 1] = (byte)0;
                cursor = cursor + 2;
                i = i + 1;
            }
            image[cursor] = (byte)0;
            image[cursor + 1] = (byte)0;
            return image;
        }

        private void WriteName(byte[] image, int offset, string name, ElfImageBuilder ascii) {
            int i = 0;
            while (i < name.Length) { image[offset + i] = (byte)ascii.AsciiCode(name[i]); i = i + 1; }
        }

        private void Write16(byte[] image, int offset, int value) {
            image[offset] = (byte)(value % 256);
            image[offset + 1] = (byte)((value / 256) % 256);
        }

        private void Write32(byte[] image, int offset, int value) {
            int temp = value;
            int i = 0;
            while (i < 4) {
                int part = temp % 256;
                if (part < 0) { part = part + 256; }
                image[offset + i] = (byte)part;
                temp = (temp - part) / 256;
                i = i + 1;
            }
        }

        private void Write64(byte[] image, int offset, int value) {
            Write32(image, offset, value);
            Write32(image, offset + 4, 0);
        }
    }
}
