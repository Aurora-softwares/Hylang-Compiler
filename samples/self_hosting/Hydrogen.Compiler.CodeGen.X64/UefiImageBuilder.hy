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
            string kernelPath = "";
            int writes = 0;
            int startImages = 0;
            int exitBootServices = 0;
            int memoryMapInitializers = 0;
            int memoryInitializers = 0;
            int virtualMemoryInitializers = 0;
            int kernelHalts = 0;
            int i = 0;
            while (i < ops.Length) {
                if (ops[i].Kind() == IrOp.KindWriteLineLiteral()) {
                    if (exitBootServices != 0) {
                        return Failed("UEFI console output must precede System.Uefi.ExitBootServices");
                    }
                    payload = payload + ops[i].Text() + "\r\n";
                    writes = writes + 1;
                } else if (ops[i].Kind() == IrOp.KindStartImageLiteral()) {
                    kernelPath = ops[i].Text();
                    startImages = startImages + 1;
                } else if (ops[i].Kind() == IrOp.KindExitBootServices()) {
                    if (kernelHalts != 0) {
                        return Failed("System.Uefi.ExitBootServices must precede System.Kernel.Halt");
                    }
                    exitBootServices = exitBootServices + 1;
                } else if (ops[i].Kind() == IrOp.KindInitializeMemoryMap()) {
                    if (exitBootServices == 0) {
                        return Failed("System.Kernel.MemoryMap.Initialize must follow System.Uefi.ExitBootServices");
                    }
                    if (kernelHalts != 0) {
                        return Failed("System.Kernel.MemoryMap.Initialize must precede System.Kernel.Halt");
                    }
                    memoryMapInitializers = memoryMapInitializers + 1;
                } else if (ops[i].Kind() == IrOp.KindInitializeKernelMemory()) {
                    if (memoryMapInitializers == 0) {
                        return Failed("System.Kernel.Memory.Initialize must follow System.Kernel.MemoryMap.Initialize");
                    }
                    if (kernelHalts != 0) {
                        return Failed("System.Kernel.Memory.Initialize must precede System.Kernel.Halt");
                    }
                    memoryInitializers = memoryInitializers + 1;
                } else if (ops[i].Kind() == IrOp.KindInitializeVirtualMemory()) {
                    if (memoryInitializers == 0) {
                        return Failed("System.Kernel.VirtualMemory.Initialize must follow System.Kernel.Memory.Initialize");
                    }
                    if (kernelHalts != 0) {
                        return Failed("System.Kernel.VirtualMemory.Initialize must precede System.Kernel.Halt");
                    }
                    virtualMemoryInitializers = virtualMemoryInitializers + 1;
                } else if (ops[i].Kind() == IrOp.KindKernelHalt()) {
                    if (exitBootServices == 0) {
                        return Failed("System.Kernel.Halt must follow System.Uefi.ExitBootServices");
                    }
                    if (memoryMapInitializers == 0) {
                        return Failed("System.Kernel.Halt must follow System.Kernel.MemoryMap.Initialize");
                    }
                    if (memoryInitializers == 0) {
                        return Failed("System.Kernel.Halt must follow System.Kernel.Memory.Initialize");
                    }
                    if (virtualMemoryInitializers == 0) {
                        return Failed("System.Kernel.Halt must follow System.Kernel.VirtualMemory.Initialize");
                    }
                    kernelHalts = kernelHalts + 1;
                } else if (ops[i].Kind() != IrOp.KindExit()) {
                    return Failed("UEFI target supports literal console output, System.Uefi.StartImage, and the kernel handoff calls");
                }
                i = i + 1;
            }
            if (writes == 0) { return Failed("UEFI target requires at least one System.Console.WriteLine string literal"); }
            if (startImages > 1) { return Failed("UEFI target supports one System.Uefi.StartImage call"); }
            if (startImages == 1 && kernelPath.Length == 0) { return Failed("UEFI image path cannot be empty"); }
            if (exitBootServices > 1) { return Failed("UEFI target supports one System.Uefi.ExitBootServices call"); }
            if (memoryMapInitializers > 1) { return Failed("UEFI target supports one System.Kernel.MemoryMap.Initialize call"); }
            if (memoryInitializers > 1) { return Failed("UEFI target supports one System.Kernel.Memory.Initialize call"); }
            if (virtualMemoryInitializers > 1) { return Failed("UEFI target supports one System.Kernel.VirtualMemory.Initialize call"); }
            if (kernelHalts > 1) { return Failed("UEFI target supports one System.Kernel.Halt call"); }
            if (startImages != 0 && exitBootServices != 0) { return Failed("a UEFI image cannot start another image and leave boot services"); }
            if (exitBootServices != 1 || memoryMapInitializers != 1 || memoryInitializers != 1 || virtualMemoryInitializers != 1 || kernelHalts != 1) {
                if (exitBootServices != 0 || memoryMapInitializers != 0 || memoryInitializers != 0 || virtualMemoryInitializers != 0 || kernelHalts != 0) {
                    return Failed("System.Uefi.ExitBootServices, System.Kernel.MemoryMap.Initialize, System.Kernel.Memory.Initialize, System.Kernel.VirtualMemory.Initialize, and System.Kernel.Halt must be used together");
                }
            }

            ElfImageBuilder ascii = new ElfImageBuilder();
            if (!ascii.SupportsPayload(payload) || !ascii.SupportsPayload(kernelPath)) {
                return Failed("UEFI target currently supports ASCII string literals only");
            }
            return new UefiImageResult(true, BuildImage(payload, kernelPath, exitBootServices == 1, memoryMapInitializers == 1, memoryInitializers == 1, virtualMemoryInitializers == 1, ascii), "");
        }

        private UefiImageResult Failed(string message) {
            return new UefiImageResult(false, new byte[0], message);
        }

        private byte[] BuildImage(string payload, string kernelPath, bool leaveBootServices, bool initializeMemoryMap, bool initializeKernelMemory, bool initializeVirtualMemory, ElfImageBuilder ascii) {
            int headers = 512;
            int textRva = 4096;
            int dataRva = 8192;
            int payloadSize = (payload.Length + 1) * 2;
            int kernelPathSize = 0;
            int loadedImageGuidOffset = 0;
            int simpleFileSystemGuidOffset = 0;
            int fileInfoGuidOffset = 0;
            int errorOffset = 0;
            int memoryMapErrorOffset = 0;
            int errorSize = 0;
            bool chainLoad = kernelPath.Length != 0;
            if (chainLoad) {
                kernelPathSize = (kernelPath.Length + 1) * 2;
                loadedImageGuidOffset = payloadSize + kernelPathSize;
                simpleFileSystemGuidOffset = loadedImageGuidOffset + 16;
                fileInfoGuidOffset = simpleFileSystemGuidOffset + 16;
                errorOffset = fileInfoGuidOffset + 16;
                errorSize = ("\r\n[BOOT] Failed to start kernel.\r\n".Length + 1) * 2;
            } else if (leaveBootServices) {
                errorOffset = payloadSize;
                memoryMapErrorOffset = errorOffset + ("\r\n[KERNEL] Failed to allocate UEFI memory map.\r\n".Length + 1) * 2;
                errorSize = ("\r\n[KERNEL] Failed to allocate UEFI memory map.\r\n".Length + 1) * 2
                    + ("\r\n[KERNEL] Failed to capture final UEFI memory map.\r\n".Length + 1) * 2;
            }
            int dataSize = payloadSize + errorSize;
            if (chainLoad) { dataSize = payloadSize + kernelPathSize + 48 + errorSize; }
            int dataRawSize = ((dataSize + 511) / 512) * 512;
            int dataVirtualSize = ((dataSize + 4095) / 4096) * 4096;
            int bootInfoSize = 0;
            int bootInfoRawSize = 0;
            int bootInfoVirtualSize = 0;
            int bootInfoRva = 0;
            if (initializeMemoryMap) {
                bootInfoSize = 72;
                bootInfoRawSize = 512;
                bootInfoVirtualSize = 4096;
                bootInfoRva = dataRva + dataVirtualSize;
            }
            int sectionCount = 2;
            int imageSize = dataRva + dataVirtualSize;
            if (initializeMemoryMap) {
                sectionCount = 3;
                imageSize = bootInfoRva + bootInfoVirtualSize;
            }

            X64Assembler code = new X64Assembler();
            EmitEntrySetup(code);
            EmitConsoleWrite(code, textRva, dataRva);
            int[] failureJumps = new int[9];
            int failureCount = 0;
            int[] kernelFailureJumps = new int[16];
            int kernelFailureCount = 0;
            if (chainLoad) {
                failureCount = EmitChainLoader(code, textRva, dataRva + payloadSize,
                    dataRva + loadedImageGuidOffset, dataRva + simpleFileSystemGuidOffset,
                    dataRva + fileInfoGuidOffset, failureJumps, failureCount);
            } else if (leaveBootServices) {
                failureCount = EmitExitBootServices(code, textRva, bootInfoRva, failureJumps, failureCount);
                if (initializeMemoryMap) {
                    EmitSetKernelBootInfoArgument(code, textRva, bootInfoRva);
                    EmitMarkMemoryMapInitialized(code, textRva, bootInfoRva);
                }
                if (initializeKernelMemory) {
                    kernelFailureCount = EmitInitializeKernelMemory(code, kernelFailureJumps, kernelFailureCount);
                }
                if (initializeVirtualMemory) {
                    kernelFailureCount = EmitInitializeVirtualMemory(code, kernelFailureJumps, kernelFailureCount);
                }
                EmitKernelHalt(code);
                if (initializeKernelMemory || initializeVirtualMemory) {
                    int kernelFailureStart = code.Position();
                    EmitKernelHalt(code);
                    int kernelFailure = 0;
                    while (kernelFailure < kernelFailureCount) {
                        code.Patch32(kernelFailureJumps[kernelFailure], kernelFailureStart - (kernelFailureJumps[kernelFailure] + 4));
                        kernelFailure = kernelFailure + 1;
                    }
                }
            }
            if (!leaveBootServices) {
                code.EmitByte(0xeb); code.EmitByte(0xfe); // leave success text visible
            }
            if (chainLoad || leaveBootServices) {
                if (chainLoad) {
                    int failureStart = code.Position();
                    EmitConsoleWrite(code, textRva, dataRva + errorOffset);
                    code.EmitByte(0xeb); code.EmitByte(0xfe);
                    int jump = 0;
                    while (jump < failureCount) {
                        code.Patch32(failureJumps[jump], failureStart - (failureJumps[jump] + 4));
                        jump = jump + 1;
                    }
                } else {
                    int allocationFailureStart = code.Position();
                    EmitConsoleWrite(code, textRva, dataRva + errorOffset);
                    code.EmitByte(0xeb); code.EmitByte(0xfe);
                    int memoryMapFailureStart = code.Position();
                    EmitConsoleWrite(code, textRva, dataRva + memoryMapErrorOffset);
                    code.EmitByte(0xeb); code.EmitByte(0xfe);
                    code.Patch32(failureJumps[0], allocationFailureStart - (failureJumps[0] + 4));
                    code.Patch32(failureJumps[1], memoryMapFailureStart - (failureJumps[1] + 4));
                }
            }
            byte[] codeBytes = code.ToArray();
            int textRawSize = ((codeBytes.Length + 511) / 512) * 512;
            int textOffset = headers;
            int dataOffset = textOffset + textRawSize;
            int bootInfoOffset = dataOffset + dataRawSize;
            byte[] image = new byte[bootInfoOffset + bootInfoRawSize];

            // MS-DOS stub and PE/COFF header.
            image[0] = (byte)77; image[1] = (byte)90;
            Write32(image, 60, 128);
            image[128] = (byte)80; image[129] = (byte)69;
            Write16(image, 132, 34404); // IMAGE_FILE_MACHINE_AMD64
            Write16(image, 134, sectionCount);
            Write16(image, 148, 240);
            Write16(image, 150, 546); // executable, large-address-aware, debug stripped

            int optional = 152;
            Write16(image, optional, 523); // PE32+
            Write32(image, optional + 4, textRawSize);
            Write32(image, optional + 8, dataRawSize + bootInfoRawSize);
            Write32(image, optional + 16, textRva);
            Write32(image, optional + 20, textRva);
            Write32(image, optional + 24, 0); // position-independent EFI image base
            Write32(image, optional + 28, 0);
            Write32(image, optional + 32, 4096);
            Write32(image, optional + 36, 512);
            Write16(image, optional + 48, 2);
            Write32(image, optional + 56, imageSize);
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
            Write32(image, section + 8, codeBytes.Length);
            Write32(image, section + 12, textRva);
            Write32(image, section + 16, textRawSize);
            Write32(image, section + 20, textOffset);
            Write32(image, section + 36, 1610612768); // code, execute, read

            int dataSection = section + 40;
            WriteName(image, dataSection, ".rdata", ascii);
            Write32(image, dataSection + 8, dataSize);
            Write32(image, dataSection + 12, dataRva);
            Write32(image, dataSection + 16, dataRawSize);
            Write32(image, dataSection + 20, dataOffset);
            Write32(image, dataSection + 36, 1073741888); // initialized data, read

            if (initializeMemoryMap) {
                int bootInfoSection = dataSection + 40;
                WriteName(image, bootInfoSection, ".data", ascii);
                Write32(image, bootInfoSection + 8, bootInfoSize);
                Write32(image, bootInfoSection + 12, bootInfoRva);
                Write32(image, bootInfoSection + 16, bootInfoRawSize);
                Write32(image, bootInfoSection + 20, bootInfoOffset);
                Write32(image, bootInfoSection + 36, -1073741760); // initialized data, read, write
            }

            int i = 0;
            while (i < codeBytes.Length) { image[textOffset + i] = codeBytes[i]; i = i + 1; }
            WriteUtf16(image, dataOffset, payload, ascii);
            if (chainLoad) {
                WriteUtf16(image, dataOffset + payloadSize, kernelPath, ascii);
                WriteLoadedImageGuid(image, dataOffset + loadedImageGuidOffset);
                WriteSimpleFileSystemGuid(image, dataOffset + simpleFileSystemGuidOffset);
                WriteFileInfoGuid(image, dataOffset + fileInfoGuidOffset);
                WriteUtf16(image, dataOffset + errorOffset, "\r\n[BOOT] Failed to start kernel.\r\n", ascii);
            } else if (leaveBootServices) {
                WriteUtf16(image, dataOffset + errorOffset, "\r\n[KERNEL] Failed to allocate UEFI memory map.\r\n", ascii);
                WriteUtf16(image, dataOffset + memoryMapErrorOffset, "\r\n[KERNEL] Failed to capture final UEFI memory map.\r\n", ascii);
            }
            if (initializeMemoryMap) {
                WriteKernelBootInfo(image, bootInfoOffset);
            }
            return image;
        }

        // EFIAPI entry receives ImageHandle in RCX and EFI_SYSTEM_TABLE in RDX.
        // Preserve them in nonvolatile registers and reserve ABI shadow space plus
        // local storage for the handles needed by the firmware file protocol.
        private void EmitEntrySetup(X64Assembler code) {
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xcc); // r12 = ImageHandle
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xd5); // r13 = SystemTable
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xec); code.Emit32(136);
        }

        private int EmitChainLoader(X64Assembler code, int textRva, int kernelPathRva,
            int loadedImageGuidRva, int simpleFileSystemGuidRva, int fileInfoGuidRva,
            int[] failureJumps, int failureCount) {
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x75); code.EmitByte(0x60); // r14 = BootServices

            // HandleProtocol(ImageHandle, LoadedImageGuid, &loadedImage).
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xe1);
            EmitLeaRdxRva(code, textRva, loadedImageGuidRva);
            EmitLeaR8Rsp(code, 48);
            EmitBootService(code, 152);
            failureJumps[failureCount] = EmitFailureJump(code); failureCount = failureCount + 1;

            // HandleProtocol(loadedImage.DeviceHandle, SimpleFileSystemGuid, &fileSystem).
            EmitMovRcxRsp(code, 48);
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x49); code.EmitByte(0x18);
            EmitLeaRdxRva(code, textRva, simpleFileSystemGuidRva);
            EmitLeaR8Rsp(code, 56);
            EmitBootService(code, 152);
            failureJumps[failureCount] = EmitFailureJump(code); failureCount = failureCount + 1;

            // root = fileSystem.OpenVolume().
            EmitMovRcxRsp(code, 56);
            EmitLeaRdxRsp(code, 64);
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x41); code.EmitByte(0x08);
            code.EmitByte(0xff); code.EmitByte(0xd0);
            failureJumps[failureCount] = EmitFailureJump(code); failureCount = failureCount + 1;

            // root.Open(&kernelFile, path, EFI_FILE_MODE_READ, 0).
            EmitMovRcxRsp(code, 64);
            EmitLeaRdxRsp(code, 72);
            EmitLeaR8Rva(code, textRva, kernelPathRva);
            code.EmitByte(0x41); code.EmitByte(0xb9); code.Emit32(1);
            EmitStoreZeroRsp(code, 32);
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x41); code.EmitByte(0x08);
            code.EmitByte(0xff); code.EmitByte(0xd0);
            failureJumps[failureCount] = EmitFailureJump(code); failureCount = failureCount + 1;

            // GetInfo first reports the required EFI_FILE_INFO allocation size.
            EmitStoreZeroRsp(code, 80);
            EmitMovRcxRsp(code, 72);
            EmitLeaRdxRva(code, textRva, fileInfoGuidRva);
            EmitLeaR8Rsp(code, 80);
            code.EmitByte(0x45); code.EmitByte(0x31); code.EmitByte(0xc9);
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x41); code.EmitByte(0x40);
            code.EmitByte(0xff); code.EmitByte(0xd0);

            // AllocatePool(EfiLoaderData, infoSize, &fileInfo).
            code.EmitByte(0xb9); code.Emit32(2);
            EmitMovRdxRsp(code, 80);
            EmitLeaR8Rsp(code, 88);
            EmitBootService(code, 64);
            failureJumps[failureCount] = EmitFailureJump(code); failureCount = failureCount + 1;

            // GetInfo again, then keep EFI_FILE_INFO.FileSize.
            EmitMovRcxRsp(code, 72);
            EmitLeaRdxRva(code, textRva, fileInfoGuidRva);
            EmitLeaR8Rsp(code, 80);
            EmitMovR9Rsp(code, 88);
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x41); code.EmitByte(0x40);
            code.EmitByte(0xff); code.EmitByte(0xd0);
            failureJumps[failureCount] = EmitFailureJump(code); failureCount = failureCount + 1;
            EmitMovRaxRsp(code, 88);
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x40); code.EmitByte(0x08);
            EmitStoreRaxRsp(code, 96);

            // AllocatePool(EfiLoaderData, kernelSize, &kernelBuffer).
            code.EmitByte(0xb9); code.Emit32(2);
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc2);
            EmitLeaR8Rsp(code, 104);
            EmitBootService(code, 64);
            failureJumps[failureCount] = EmitFailureJump(code); failureCount = failureCount + 1;

            // kernelFile.Read(&kernelSize, kernelBuffer).
            EmitMovRcxRsp(code, 72);
            EmitLeaRdxRsp(code, 96);
            EmitMovR8Rsp(code, 104);
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x41); code.EmitByte(0x20);
            code.EmitByte(0xff); code.EmitByte(0xd0);
            failureJumps[failureCount] = EmitFailureJump(code); failureCount = failureCount + 1;

            // LoadImage(false, ImageHandle, null, kernelBuffer, kernelSize, &kernelImage).
            code.EmitByte(0x31); code.EmitByte(0xc9);
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xe2);
            code.EmitByte(0x45); code.EmitByte(0x31); code.EmitByte(0xc0);
            EmitMovR9Rsp(code, 104);
            EmitMovRaxRsp(code, 96);
            EmitStoreRaxRsp(code, 32);
            EmitLeaRaxRsp(code, 112);
            EmitStoreRaxRsp(code, 40);
            EmitBootService(code, 200);
            failureJumps[failureCount] = EmitFailureJump(code); failureCount = failureCount + 1;

            // StartImage(kernelImage, null, null). A running kernel normally does not return.
            EmitMovRcxRsp(code, 112);
            code.EmitByte(0x31); code.EmitByte(0xd2);
            code.EmitByte(0x45); code.EmitByte(0x31); code.EmitByte(0xc0);
            EmitBootService(code, 208);
            return failureCount;
        }

        // Capture a memory map after the final allocation, then retry the
        // GetMemoryMap/ExitBootServices pair when firmware invalidates its map
        // key. Once ExitBootServices has been attempted, failures halt without
        // further firmware calls or console output because shutdown may be partial.
        private int EmitExitBootServices(X64Assembler code, int textRva, int bootInfoRva, int[] failureJumps, int failureCount) {
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x75); code.EmitByte(0x60); // r14 = BootServices

            // GetMemoryMap(&memoryMapSize, null, &mapKey, &descriptorSize, &descriptorVersion).
            EmitStoreZeroRsp(code, 48);
            EmitLeaRcxRsp(code, 48);
            code.EmitByte(0x31); code.EmitByte(0xd2);
            EmitLeaR8Rsp(code, 56);
            EmitLeaR9Rsp(code, 64);
            EmitLeaRaxRsp(code, 72);
            EmitStoreRaxRsp(code, 32);
            EmitBootService(code, 56);

            // Allocate enough room for the map and sixty-four new descriptors.
            code.EmitByte(0xb9); code.Emit32(2); // EfiLoaderData
            EmitMovRdxRsp(code, 48);
            EmitMovRaxRsp(code, 64);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe0); code.EmitByte(0x06);
            code.EmitByte(0x48); code.EmitByte(0x01); code.EmitByte(0xc2);
            EmitStoreRdxRsp(code, 48);
            EmitStoreRdxRsp(code, 120); // fixed capacity for every retry
            EmitLeaR8Rsp(code, 80);
            EmitBootService(code, 64);
            failureJumps[failureCount] = EmitFailureJump(code); failureCount = failureCount + 1;

            // The first failed ExitBootServices attempt sets R15D nonzero. From
            // that point an unsuccessful GetMemoryMap must halt rather than use
            // a firmware console failure path.
            code.EmitByte(0x45); code.EmitByte(0x31); code.EmitByte(0xff); // r15d = 0
            int mapStart = code.Position();
            EmitMovRaxRsp(code, 120);
            EmitStoreRaxRsp(code, 48);
            EmitLeaRcxRsp(code, 48);
            EmitMovRdxRsp(code, 80);
            EmitLeaR8Rsp(code, 56);
            EmitLeaR9Rsp(code, 64);
            EmitLeaRaxRsp(code, 72);
            EmitStoreRaxRsp(code, 32);
            EmitBootService(code, 56);
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xc0);
            int memoryMapSucceeded = EmitConditionalJump(code, 0x84); // jz
            code.EmitByte(0x4d); code.EmitByte(0x85); code.EmitByte(0xff); // test r15, r15
            int retriedMemoryMapFailure = EmitConditionalJump(code, 0x85); // jnz
            failureJumps[failureCount] = EmitFailureJump(code); failureCount = failureCount + 1;

            int postExitFailure = code.Position();
            EmitKernelHalt(code);
            int memoryMapSucceededAt = code.Position();
            code.Patch32(memoryMapSucceeded, memoryMapSucceededAt - (memoryMapSucceeded + 4));
            code.Patch32(retriedMemoryMapFailure, postExitFailure - (retriedMemoryMapFailure + 4));

            // The final map values become the kernel's stable boot-information ABI.
            EmitMovRaxRsp(code, 80);
            EmitStoreRaxRva(code, textRva, bootInfoRva + 8);
            EmitMovRaxRsp(code, 48);
            EmitStoreRaxRva(code, textRva, bootInfoRva + 16);
            EmitMovRaxRsp(code, 64);
            EmitStoreRaxRva(code, textRva, bootInfoRva + 24);
            EmitMovEaxRsp(code, 72);
            EmitStoreRaxRva(code, textRva, bootInfoRva + 32);

            // ExitBootServices(ImageHandle, mapKey). Success returns to kernel code.
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xe1);
            EmitMovRdxRsp(code, 56);
            EmitBootService(code, 216);
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xc0);
            int exitBootServicesSucceeded = EmitConditionalJump(code, 0x84); // jz
            code.EmitByte(0x41); code.EmitByte(0xff); code.EmitByte(0xc7); // r15d++
            code.EmitByte(0x41); code.EmitByte(0x83); code.EmitByte(0xff); code.EmitByte(8);
            int retriesExhausted = EmitConditionalJump(code, 0x83); // jae
            EmitJumpTo(code, mapStart);

            int exitBootServicesSucceededAt = code.Position();
            code.Patch32(exitBootServicesSucceeded, exitBootServicesSucceededAt - (exitBootServicesSucceeded + 4));
            code.Patch32(retriesExhausted, postExitFailure - (retriesExhausted + 4));
            return failureCount;
        }

        // The constrained UEFI target follows the native Hydrogen x64 convention:
        // RDI carries the first kernel argument, the KernelBootInfo pointer.
        private void EmitSetKernelBootInfoArgument(X64Assembler code, int textRva, int bootInfoRva) {
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x3d);
            code.Emit32(bootInfoRva - (textRva + code.Position() + 4));
        }

        // This store happens after ExitBootServices succeeds. It marks the data
        // record ready for the next Hydrogen kernel implementation to consume.
        private void EmitMarkMemoryMapInitialized(X64Assembler code, int textRva, int bootInfoRva) {
            EmitStore32Rva(code, textRva, bootInfoRva + 36, 1);
        }

        // Build a page-aligned bump allocator from the largest
        // EfiConventionalMemory descriptor. The first page is zeroed as reserved
        // allocator metadata; subsequent pages form the initial free range.
        private int EmitInitializeKernelMemory(X64Assembler code, int[] failureJumps, int failureCount) {
            // Validate KernelBootInfo before reading the firmware-owned map.
            code.EmitByte(0x81); code.EmitByte(0x3f); code.Emit32(1229083969); // "AUBI"
            failureJumps[failureCount] = EmitConditionalJump(code, 0x85); failureCount = failureCount + 1; // jne
            code.EmitByte(0x83); code.EmitByte(0x7f); code.EmitByte(0x04); code.EmitByte(0x01);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x85); failureCount = failureCount + 1; // jne
            code.EmitByte(0x83); code.EmitByte(0x7f); code.EmitByte(0x24); code.EmitByte(0x01);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x85); failureCount = failureCount + 1; // jne

            // Keep the boot-information pointer while RDI clears the metadata page.
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xff); // r15 = rdi
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x47); code.EmitByte(0x08); // r8 = map
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x4f); code.EmitByte(0x10); // r9 = map size
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x57); code.EmitByte(0x18); // r10 = descriptor size
            code.EmitByte(0x4d); code.EmitByte(0x85); code.EmitByte(0xc0); // test r8, r8
            failureJumps[failureCount] = EmitConditionalJump(code, 0x84); failureCount = failureCount + 1; // jz
            code.EmitByte(0x4d); code.EmitByte(0x85); code.EmitByte(0xc9); // test r9, r9
            failureJumps[failureCount] = EmitConditionalJump(code, 0x84); failureCount = failureCount + 1; // jz
            code.EmitByte(0x49); code.EmitByte(0x83); code.EmitByte(0xfa); code.EmitByte(40); // cmp r10, 40
            failureJumps[failureCount] = EmitConditionalJump(code, 0x82); failureCount = failureCount + 1; // jb
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xc3); // r11 = r8
            code.EmitByte(0x4d); code.EmitByte(0x01); code.EmitByte(0xcb); // r11 += r9
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xc3); // cmp r11, r8
            failureJumps[failureCount] = EmitConditionalJump(code, 0x86); failureCount = failureCount + 1; // jbe
            code.EmitByte(0x45); code.EmitByte(0x31); code.EmitByte(0xe4); // r12 = 0 pages found

            int scanStart = code.Position();
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xd8); // cmp r8, r11
            int scanEndJump = EmitConditionalJump(code, 0x83); // jae
            int[] advanceJumps = new int[3];
            code.EmitByte(0x41); code.EmitByte(0x83); code.EmitByte(0x38); code.EmitByte(7); // EfiConventionalMemory
            advanceJumps[0] = EmitConditionalJump(code, 0x85); // jne
            code.EmitByte(0x49); code.EmitByte(0x8b); code.EmitByte(0x40); code.EmitByte(0x18); // rax = NumberOfPages
            code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xf8); code.EmitByte(2);
            advanceJumps[1] = EmitConditionalJump(code, 0x82); // jb
            code.EmitByte(0x4c); code.EmitByte(0x39); code.EmitByte(0xe0); // cmp rax, r12
            advanceJumps[2] = EmitConditionalJump(code, 0x86); // jbe
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xc4); // r12 = NumberOfPages
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x68); code.EmitByte(0x08); // r13 = PhysicalStart

            int advanceStart = code.Position();
            int advance = 0;
            while (advance < advanceJumps.Length) {
                code.Patch32(advanceJumps[advance], advanceStart - (advanceJumps[advance] + 4));
                advance = advance + 1;
            }
            code.EmitByte(0x4d); code.EmitByte(0x01); code.EmitByte(0xd0); // r8 += descriptor size
            EmitJumpTo(code, scanStart);

            int scanEnd = code.Position();
            code.Patch32(scanEndJump, scanEnd - (scanEndJump + 4));
            code.EmitByte(0x4d); code.EmitByte(0x85); code.EmitByte(0xe4); // test r12, r12
            failureJumps[failureCount] = EmitConditionalJump(code, 0x84); failureCount = failureCount + 1; // jz

            // allocatorLimit = physicalStart + NumberOfPages * 4096.
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xe6); // rsi = r12
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe6); code.EmitByte(12);
            code.EmitByte(0x4c); code.EmitByte(0x01); code.EmitByte(0xee); // rsi += r13

            // Reserve and clear the first page for allocator metadata.
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xef); // rdi = r13
            code.EmitByte(0x31); code.EmitByte(0xc0);
            code.EmitByte(0xb9); code.Emit32(512);
            code.EmitByte(0xfc); // cld
            code.EmitByte(0xf3); code.EmitByte(0x48); code.EmitByte(0xab); // rep stosq
            code.EmitByte(0x49); code.EmitByte(0x8d); code.EmitByte(0x95); code.Emit32(4096); // rdx = r13 + page

            // Publish the allocator range and metadata page through KernelBootInfo.
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0x57); code.EmitByte(40);
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0x77); code.EmitByte(48);
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0x6f); code.EmitByte(56);
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xff); // rdi = r15
            code.EmitByte(0xc7); code.EmitByte(0x47); code.EmitByte(36); code.Emit32(3);
            return failureCount;
        }

        // Allocate a new PML4 page from the bootstrap range, clone the active
        // top-level map into it, and make the clone active through CR3. Keeping
        // all present entries preserves the executable image and handoff record
        // while later stages replace the inherited lower-level mappings.
        private int EmitInitializeVirtualMemory(X64Assembler code, int[] failureJumps, int failureCount) {
            code.EmitByte(0x83); code.EmitByte(0x7f); code.EmitByte(36); code.EmitByte(3);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x85); failureCount = failureCount + 1; // jne
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xff); // r15 = boot info
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x47); code.EmitByte(40); // r8 = next page
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x4f); code.EmitByte(48); // r9 = page limit
            code.EmitByte(0x4d); code.EmitByte(0x85); code.EmitByte(0xc0); // test r8, r8
            failureJumps[failureCount] = EmitConditionalJump(code, 0x84); failureCount = failureCount + 1; // jz
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xc2); // r10 = r8
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xc2); code.Emit32(4096); // r10 = r8 + page
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xc2); // cmp r10, r8
            failureJumps[failureCount] = EmitConditionalJump(code, 0x86); failureCount = failureCount + 1; // jbe overflow
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xca); // cmp r10, r9
            failureJumps[failureCount] = EmitConditionalJump(code, 0x87); failureCount = failureCount + 1; // ja exhausted

            // CR3 holds the current PML4 physical address. The current UEFI
            // mappings make physical memory directly accessible until the clone
            // becomes active, exactly as the physical allocator already uses it.
            code.EmitByte(0x0f); code.EmitByte(0x20); code.EmitByte(0xde); // rsi = cr3
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xe6); code.Emit32(-4096);
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xf6); // test rsi, rsi
            failureJumps[failureCount] = EmitConditionalJump(code, 0x84); failureCount = failureCount + 1; // jz
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xc7); // rdi = r8
            code.EmitByte(0xb9); code.Emit32(512);
            code.EmitByte(0xfc); // cld
            code.EmitByte(0xf3); code.EmitByte(0x48); code.EmitByte(0xa5); // rep movsq

            // Publish the root before the serializing CR3 write. R10 retains
            // the post-allocation page pointer across the copy operation.
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0x57); code.EmitByte(40);
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0x47); code.EmitByte(64);
            code.EmitByte(0x41); code.EmitByte(0x0f); code.EmitByte(0x22); code.EmitByte(0xd8); // cr3 = r8
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xff); // rdi = r15
            code.EmitByte(0xc7); code.EmitByte(0x47); code.EmitByte(36); code.Emit32(7);
            return failureCount;
        }

        private void EmitKernelHalt(X64Assembler code) {
            code.EmitByte(0xfa); // cli
            code.EmitByte(0xf4); // hlt
            code.EmitByte(0xeb); code.EmitByte(0xfd); // retry hlt if an NMI wakes the CPU
        }

        private void EmitConsoleWrite(X64Assembler code, int textRva, int messageRva) {
            code.EmitByte(0x49); code.EmitByte(0x8b); code.EmitByte(0x45); code.EmitByte(0x40);
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc1);
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x41); code.EmitByte(0x08);
            EmitLeaRdxRva(code, textRva, messageRva);
            code.EmitByte(0xff); code.EmitByte(0xd0);
        }

        private void EmitBootService(X64Assembler code, int offset) {
            code.EmitByte(0x49); code.EmitByte(0x8b); code.EmitByte(0x86); code.Emit32(offset);
            code.EmitByte(0xff); code.EmitByte(0xd0);
        }

        private int EmitFailureJump(X64Assembler code) {
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xc0);
            return EmitConditionalJump(code, 0x85);
        }

        private int EmitConditionalJump(X64Assembler code, int condition) {
            code.EmitByte(0x0f); code.EmitByte(condition);
            int patch = code.Position();
            code.Emit32(0);
            return patch;
        }

        private void EmitJumpTo(X64Assembler code, int target) {
            code.EmitByte(0xe9);
            code.Emit32(target - (code.Position() + 4));
        }

        private void EmitLeaRdxRva(X64Assembler code, int textRva, int targetRva) {
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x15);
            code.Emit32(targetRva - (textRva + code.Position() + 4));
        }

        private void EmitStoreRaxRva(X64Assembler code, int textRva, int targetRva) {
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x05);
            code.Emit32(targetRva - (textRva + code.Position() + 4));
        }

        private void EmitStore32Rva(X64Assembler code, int textRva, int targetRva, int value) {
            code.EmitByte(0xc7); code.EmitByte(0x05);
            code.Emit32(targetRva - (textRva + code.Position() + 4));
            code.Emit32(value);
        }

        private void EmitLeaR8Rva(X64Assembler code, int textRva, int targetRva) {
            code.EmitByte(0x4c); code.EmitByte(0x8d); code.EmitByte(0x05);
            code.Emit32(targetRva - (textRva + code.Position() + 4));
        }

        private void EmitLeaRdxRsp(X64Assembler code, int offset) {
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x54); code.EmitByte(0x24); code.EmitByte(offset);
        }

        private void EmitLeaR8Rsp(X64Assembler code, int offset) {
            code.EmitByte(0x4c); code.EmitByte(0x8d); code.EmitByte(0x44); code.EmitByte(0x24); code.EmitByte(offset);
        }

        private void EmitLeaR9Rsp(X64Assembler code, int offset) {
            code.EmitByte(0x4c); code.EmitByte(0x8d); code.EmitByte(0x4c); code.EmitByte(0x24); code.EmitByte(offset);
        }

        private void EmitLeaRaxRsp(X64Assembler code, int offset) {
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x44); code.EmitByte(0x24); code.EmitByte(offset);
        }

        private void EmitMovRcxRsp(X64Assembler code, int offset) {
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x4c); code.EmitByte(0x24); code.EmitByte(offset);
        }

        private void EmitLeaRcxRsp(X64Assembler code, int offset) {
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x4c); code.EmitByte(0x24); code.EmitByte(offset);
        }

        private void EmitMovRdxRsp(X64Assembler code, int offset) {
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x54); code.EmitByte(0x24); code.EmitByte(offset);
        }

        private void EmitMovR8Rsp(X64Assembler code, int offset) {
            code.EmitByte(0x4c); code.EmitByte(0x8b); code.EmitByte(0x44); code.EmitByte(0x24); code.EmitByte(offset);
        }

        private void EmitMovR9Rsp(X64Assembler code, int offset) {
            code.EmitByte(0x4c); code.EmitByte(0x8b); code.EmitByte(0x4c); code.EmitByte(0x24); code.EmitByte(offset);
        }

        private void EmitMovRaxRsp(X64Assembler code, int offset) {
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x44); code.EmitByte(0x24); code.EmitByte(offset);
        }

        private void EmitMovEaxRsp(X64Assembler code, int offset) {
            code.EmitByte(0x8b); code.EmitByte(0x44); code.EmitByte(0x24); code.EmitByte(offset);
        }

        private void EmitStoreRaxRsp(X64Assembler code, int offset) {
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x44); code.EmitByte(0x24); code.EmitByte(offset);
        }

        private void EmitStoreRdxRsp(X64Assembler code, int offset) {
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x54); code.EmitByte(0x24); code.EmitByte(offset);
        }

        private void EmitStoreZeroRsp(X64Assembler code, int offset) {
            code.EmitByte(0x31); code.EmitByte(0xc0);
            EmitStoreRaxRsp(code, offset);
        }

        private void WriteUtf16(byte[] image, int offset, string text, ElfImageBuilder ascii) {
            int i = 0;
            while (i < text.Length) {
                image[offset + i * 2] = (byte)ascii.AsciiCode(text[i]);
                image[offset + i * 2 + 1] = (byte)0;
                i = i + 1;
            }
            image[offset + text.Length * 2] = (byte)0;
            image[offset + text.Length * 2 + 1] = (byte)0;
        }

        // KernelBootInfo: magic "AUBI", ABI version, EFI memory-map pointer,
        // byte size, descriptor size, descriptor version, state flags, then
        // physical-page next, limit, metadata-page, and active PML4 addresses.
        private void WriteKernelBootInfo(byte[] image, int offset) {
            Write32(image, offset, 1229083969); // "AUBI" in little-endian order
            Write32(image, offset + 4, 1);
        }

        private void WriteLoadedImageGuid(byte[] image, int offset) {
            int[] bytes = new int[16];
            bytes[0] = 161; bytes[1] = 49; bytes[2] = 27; bytes[3] = 91; bytes[4] = 98; bytes[5] = 149; bytes[6] = 210; bytes[7] = 17;
            bytes[8] = 142; bytes[9] = 63; bytes[10] = 0; bytes[11] = 160; bytes[12] = 201; bytes[13] = 105; bytes[14] = 114; bytes[15] = 59;
            WriteGuid(image, offset, bytes);
        }

        private void WriteSimpleFileSystemGuid(byte[] image, int offset) {
            int[] bytes = new int[16];
            bytes[0] = 34; bytes[1] = 91; bytes[2] = 78; bytes[3] = 150; bytes[4] = 89; bytes[5] = 100; bytes[6] = 210; bytes[7] = 17;
            bytes[8] = 142; bytes[9] = 57; bytes[10] = 0; bytes[11] = 160; bytes[12] = 201; bytes[13] = 105; bytes[14] = 114; bytes[15] = 59;
            WriteGuid(image, offset, bytes);
        }

        private void WriteFileInfoGuid(byte[] image, int offset) {
            int[] bytes = new int[16];
            bytes[0] = 146; bytes[1] = 110; bytes[2] = 87; bytes[3] = 9; bytes[4] = 63; bytes[5] = 109; bytes[6] = 210; bytes[7] = 17;
            bytes[8] = 142; bytes[9] = 57; bytes[10] = 0; bytes[11] = 160; bytes[12] = 201; bytes[13] = 105; bytes[14] = 114; bytes[15] = 59;
            WriteGuid(image, offset, bytes);
        }

        private void WriteGuid(byte[] image, int offset, int[] bytes) {
            int i = 0;
            while (i < bytes.Length) { image[offset + i] = (byte)bytes[i]; i = i + 1; }
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
