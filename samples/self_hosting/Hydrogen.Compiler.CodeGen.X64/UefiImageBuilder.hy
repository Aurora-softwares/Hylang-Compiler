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
            int mappingPolicyInitializers = 0;
            int pageAllocations = 0;
            int heapInitializers = 0;
            int[] heapAllocationSizes = new int[ops.Length];
            int heapAllocations = 0;
            int framebufferInitializers = 0;
            string[] framebufferMessages = new string[ops.Length];
            int framebufferWrites = 0;
            int kernelHalts = 0;
            int clearScreens = 0;
            int awaitKeys = 0;
            int i = 0;
            while (i < ops.Length) {
                if (ops[i].Kind() == IrOp.KindClearScreen()) {
                    if (writes != 0) {
                        return Failed("System.Uefi.ClearScreen must precede console output");
                    }
                    if (exitBootServices != 0) {
                        return Failed("System.Uefi.ClearScreen must precede System.Uefi.ExitBootServices");
                    }
                    clearScreens = clearScreens + 1;
                } else if (ops[i].Kind() == IrOp.KindWriteLineLiteral()) {
                    if (exitBootServices != 0) {
                        return Failed("UEFI console output must precede System.Uefi.ExitBootServices");
                    }
                    payload = payload + ops[i].Text() + "\r\n";
                    writes = writes + 1;
                } else if (ops[i].Kind() == IrOp.KindAwaitKey()) {
                    if (exitBootServices != 0) {
                        return Failed("System.Uefi.Await must precede System.Uefi.ExitBootServices");
                    }
                    if (writes == 0) {
                        return Failed("System.Uefi.Await must follow console output");
                    }
                    if (startImages != 0) {
                        return Failed("System.Uefi.Await must precede System.Uefi.StartImage");
                    }
                    awaitKeys = awaitKeys + 1;
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
                } else if (ops[i].Kind() == IrOp.KindApplyKernelMappingPolicy()) {
                    if (virtualMemoryInitializers == 0) {
                        return Failed("System.Kernel.VirtualMemory.ApplyPolicy must follow System.Kernel.VirtualMemory.Initialize");
                    }
                    if (kernelHalts != 0) {
                        return Failed("System.Kernel.VirtualMemory.ApplyPolicy must precede System.Kernel.Halt");
                    }
                    mappingPolicyInitializers = mappingPolicyInitializers + 1;
                } else if (ops[i].Kind() == IrOp.KindAllocateKernelPage()) {
                    if (mappingPolicyInitializers == 0) {
                        return Failed("System.Kernel.Memory.AllocatePage must follow System.Kernel.VirtualMemory.ApplyPolicy");
                    }
                    if (heapInitializers != 0) {
                        return Failed("System.Kernel.Memory.AllocatePage must precede System.Kernel.Heap.Initialize");
                    }
                    if (kernelHalts != 0) {
                        return Failed("System.Kernel.Memory.AllocatePage must precede System.Kernel.Halt");
                    }
                    pageAllocations = pageAllocations + 1;
                } else if (ops[i].Kind() == IrOp.KindInitializeKernelHeap()) {
                    if (mappingPolicyInitializers == 0) {
                        return Failed("System.Kernel.Heap.Initialize must follow System.Kernel.VirtualMemory.ApplyPolicy");
                    }
                    if (kernelHalts != 0) {
                        return Failed("System.Kernel.Heap.Initialize must precede System.Kernel.Halt");
                    }
                    heapInitializers = heapInitializers + 1;
                } else if (ops[i].Kind() == IrOp.KindAllocateKernelHeap()) {
                    if (heapInitializers == 0) {
                        return Failed("System.Kernel.Heap.Allocate must follow System.Kernel.Heap.Initialize");
                    }
                    if (ops[i].ExitCode() <= 0 || ops[i].ExitCode() > 1048576) {
                        return Failed("System.Kernel.Heap.Allocate requires a literal byte count from 1 through 1048576");
                    }
                    if (kernelHalts != 0) {
                        return Failed("System.Kernel.Heap.Allocate must precede System.Kernel.Halt");
                    }
                    heapAllocationSizes[heapAllocations] = ops[i].ExitCode();
                    heapAllocations = heapAllocations + 1;
                } else if (ops[i].Kind() == IrOp.KindInitializeFramebuffer()) {
                    if (heapInitializers == 0) {
                        return Failed("System.Kernel.Framebuffer.Initialize must follow System.Kernel.Heap.Initialize");
                    }
                    if (kernelHalts != 0) {
                        return Failed("System.Kernel.Framebuffer.Initialize must precede System.Kernel.Halt");
                    }
                    framebufferInitializers = framebufferInitializers + 1;
                } else if (ops[i].Kind() == IrOp.KindFramebufferWriteLineLiteral()) {
                    if (framebufferInitializers == 0) {
                        return Failed("System.Kernel.Framebuffer.WriteLine must follow System.Kernel.Framebuffer.Initialize");
                    }
                    if (kernelHalts != 0) {
                        return Failed("System.Kernel.Framebuffer.WriteLine must precede System.Kernel.Halt");
                    }
                    framebufferMessages[framebufferWrites] = ops[i].Text();
                    framebufferWrites = framebufferWrites + 1;
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
                    if (mappingPolicyInitializers == 0) {
                        return Failed("System.Kernel.Halt must follow System.Kernel.VirtualMemory.ApplyPolicy");
                    }
                    if (heapInitializers == 0) {
                        return Failed("System.Kernel.Halt must follow System.Kernel.Heap.Initialize");
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
            if (mappingPolicyInitializers > 1) { return Failed("UEFI target supports one System.Kernel.VirtualMemory.ApplyPolicy call"); }
            if (heapInitializers > 1) { return Failed("UEFI target supports one System.Kernel.Heap.Initialize call"); }
            if (framebufferInitializers > 1) { return Failed("UEFI target supports one System.Kernel.Framebuffer.Initialize call"); }
            if (kernelHalts > 1) { return Failed("UEFI target supports one System.Kernel.Halt call"); }
            if (clearScreens > 1) { return Failed("UEFI target supports one System.Uefi.ClearScreen call"); }
            if (startImages != 0 && exitBootServices != 0) { return Failed("a UEFI image cannot start another image and leave boot services"); }
            if (exitBootServices != 1 || memoryMapInitializers != 1 || memoryInitializers != 1 || virtualMemoryInitializers != 1 || mappingPolicyInitializers != 1 || heapInitializers != 1 || kernelHalts != 1) {
                if (exitBootServices != 0 || memoryMapInitializers != 0 || memoryInitializers != 0 || virtualMemoryInitializers != 0 || mappingPolicyInitializers != 0 || heapInitializers != 0 || kernelHalts != 0) {
                    return Failed("System.Uefi.ExitBootServices, System.Kernel.MemoryMap.Initialize, System.Kernel.Memory.Initialize, System.Kernel.VirtualMemory.Initialize, System.Kernel.VirtualMemory.ApplyPolicy, System.Kernel.Heap.Initialize, and System.Kernel.Halt must be used together");
                }
            }

            ElfImageBuilder ascii = new ElfImageBuilder();
            if (!ascii.SupportsPayload(payload) || !ascii.SupportsPayload(kernelPath)) {
                return Failed("UEFI target currently supports ASCII string literals only");
            }
            int framebufferMessage = 0;
            while (framebufferMessage < framebufferWrites) {
                if (!ascii.SupportsPayload(framebufferMessages[framebufferMessage])) {
                    return Failed("UEFI target currently supports ASCII string literals only");
                }
                framebufferMessage = framebufferMessage + 1;
            }
            return new UefiImageResult(true, BuildImage(payload, kernelPath, clearScreens == 1, awaitKeys, exitBootServices == 1, memoryMapInitializers == 1, memoryInitializers == 1, virtualMemoryInitializers == 1, mappingPolicyInitializers == 1, pageAllocations, heapInitializers == 1, heapAllocationSizes, heapAllocations, framebufferInitializers == 1, framebufferMessages, framebufferWrites, ascii), "");
        }

        private UefiImageResult Failed(string message) {
            return new UefiImageResult(false, new byte[0], message);
        }

        private byte[] BuildImage(string payload, string kernelPath, bool clearScreen, int awaitKeyCount, bool leaveBootServices, bool initializeMemoryMap, bool initializeKernelMemory, bool initializeVirtualMemory, bool applyMappingPolicy, int pageAllocationCount, bool initializeKernelHeap, int[] heapAllocationSizes, int heapAllocationCount, bool initializeFramebuffer, string[] framebufferMessages, int framebufferWriteCount, ElfImageBuilder ascii) {
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
            int framebufferErrorOffset = 0;
            int graphicsOutputGuidOffset = 0;
            int framebufferFontOffset = 0;
            int[] framebufferMessageOffsets = new int[framebufferWriteCount];
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
            if (initializeFramebuffer) {
                framebufferErrorOffset = dataSize;
                graphicsOutputGuidOffset = framebufferErrorOffset + ("\r\n[KERNEL] GOP framebuffer is unavailable.\r\n".Length + 1) * 2;
                framebufferFontOffset = graphicsOutputGuidOffset + 16;
                int framebufferDataEnd = framebufferFontOffset + 760;
                int framebufferMessage = 0;
                while (framebufferMessage < framebufferWriteCount) {
                    framebufferMessageOffsets[framebufferMessage] = framebufferDataEnd;
                    framebufferDataEnd = framebufferDataEnd + framebufferMessages[framebufferMessage].Length + 1;
                    framebufferMessage = framebufferMessage + 1;
                }
                dataSize = framebufferDataEnd;
            }
            int dataRawSize = ((dataSize + 511) / 512) * 512;
            int dataVirtualSize = ((dataSize + 4095) / 4096) * 4096;
            int bootInfoSize = 0;
            int bootInfoRawSize = 0;
            int bootInfoVirtualSize = 0;
            int bootInfoRva = 0;
            if (initializeMemoryMap) {
                bootInfoSize = 152;
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
            if (clearScreen) { EmitClearScreen(code); }
            EmitConsoleWrite(code, textRva, dataRva);
            int awaitIndex = 0;
            while (awaitIndex < awaitKeyCount) {
                EmitAwaitKey(code);
                awaitIndex = awaitIndex + 1;
            }
            int[] failureJumps = new int[9];
            int failureCount = 0;
            int[] kernelFailureJumps = new int[(pageAllocationCount + heapAllocationCount) * 8 + framebufferWriteCount + 40];
            int kernelFailureCount = 0;
            int framebufferFailureJump = -1;
            if (chainLoad) {
                failureCount = EmitChainLoader(code, textRva, dataRva + payloadSize,
                    dataRva + loadedImageGuidOffset, dataRva + simpleFileSystemGuidOffset,
                    dataRva + fileInfoGuidOffset, failureJumps, failureCount);
            } else if (leaveBootServices) {
                if (initializeFramebuffer) {
                    framebufferFailureJump = EmitCaptureFramebuffer(code, textRva, bootInfoRva,
                        dataRva + graphicsOutputGuidOffset);
                }
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
                if (applyMappingPolicy) {
                    kernelFailureCount = EmitApplyKernelMappingPolicy(code, kernelFailureJumps, kernelFailureCount);
                }
                int pageAllocation = 0;
                while (pageAllocation < pageAllocationCount) {
                    kernelFailureCount = EmitAllocateKernelPage(code, kernelFailureJumps, kernelFailureCount);
                    pageAllocation = pageAllocation + 1;
                }
                if (initializeKernelHeap) {
                    kernelFailureCount = EmitInitializeKernelHeap(code, kernelFailureJumps, kernelFailureCount);
                }
                int heapAllocation = 0;
                while (heapAllocation < heapAllocationCount) {
                    kernelFailureCount = EmitAllocateKernelHeap(code, heapAllocationSizes[heapAllocation], kernelFailureJumps, kernelFailureCount);
                    heapAllocation = heapAllocation + 1;
                }
                if (initializeFramebuffer) {
                    kernelFailureCount = EmitInitializeFramebuffer(code, kernelFailureJumps, kernelFailureCount);
                    int framebufferMessage = 0;
                    while (framebufferMessage < framebufferWriteCount) {
                        kernelFailureCount = EmitFramebufferWriteLine(code, textRva, bootInfoRva,
                            dataRva + framebufferFontOffset, dataRva + framebufferMessageOffsets[framebufferMessage],
                            kernelFailureJumps, kernelFailureCount);
                        framebufferMessage = framebufferMessage + 1;
                    }
                }
                EmitKernelHalt(code);
                if (initializeKernelMemory || initializeVirtualMemory || applyMappingPolicy || pageAllocationCount != 0 || initializeKernelHeap || heapAllocationCount != 0 || initializeFramebuffer) {
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
                    if (initializeFramebuffer) {
                        int framebufferFailureStart = code.Position();
                        EmitConsoleWrite(code, textRva, dataRva + framebufferErrorOffset);
                        code.EmitByte(0xeb); code.EmitByte(0xfe);
                        code.Patch32(framebufferFailureJump, framebufferFailureStart - (framebufferFailureJump + 4));
                    }
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
            if (initializeFramebuffer) {
                WriteUtf16(image, dataOffset + framebufferErrorOffset, "\r\n[KERNEL] GOP framebuffer is unavailable.\r\n", ascii);
                WriteGraphicsOutputGuid(image, dataOffset + graphicsOutputGuidOffset);
                WriteFramebufferFont(image, dataOffset + framebufferFontOffset);
                int framebufferMessage = 0;
                while (framebufferMessage < framebufferWriteCount) {
                    WriteAscii(image, dataOffset + framebufferMessageOffsets[framebufferMessage], framebufferMessages[framebufferMessage], ascii);
                    framebufferMessage = framebufferMessage + 1;
                }
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

        // EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL.ClearScreen(This) uses the same
        // ConsoleOut protocol as OutputString. It runs before any boot text.
        private void EmitClearScreen(X64Assembler code) {
            code.EmitByte(0x49); code.EmitByte(0x8b); code.EmitByte(0x4d); code.EmitByte(0x40); // rcx = ConOut
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x41); code.EmitByte(0x30); // rax = ClearScreen
            code.EmitByte(0xff); code.EmitByte(0xd0);
        }

        // Wait for one UEFI key event, then consume its EFI_INPUT_KEY record.
        // Local storage begins above the Microsoft x64 ABI shadow space.
        private void EmitAwaitKey(X64Assembler code) {
            code.EmitByte(0x49); code.EmitByte(0x8b); code.EmitByte(0x45); code.EmitByte(0x30); // rax = ConIn
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x40); code.EmitByte(0x10); // rax = WaitForKey event
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x44); code.EmitByte(0x24); code.EmitByte(48); // event[0]
            code.EmitByte(0xb9); code.Emit32(1); // NumberOfEvents
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x54); code.EmitByte(0x24); code.EmitByte(48); // events
            code.EmitByte(0x4c); code.EmitByte(0x8d); code.EmitByte(0x44); code.EmitByte(0x24); code.EmitByte(56); // index
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x75); code.EmitByte(0x60); // r14 = BootServices
            EmitBootService(code, 96); // WaitForEvent(1, events, &index)

            code.EmitByte(0x49); code.EmitByte(0x8b); code.EmitByte(0x4d); code.EmitByte(0x30); // rcx = ConIn
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x54); code.EmitByte(0x24); code.EmitByte(64); // EFI_INPUT_KEY
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x41); code.EmitByte(8); // rax = ReadKeyStroke
            code.EmitByte(0xff); code.EmitByte(0xd0);
        }

        // Locate the Graphics Output Protocol while boot services are still
        // available. The values copied here are plain framebuffer geometry and
        // remain usable after ExitBootServices; no GOP function is called by
        // the post-handoff renderer.
        private int EmitCaptureFramebuffer(X64Assembler code, int textRva, int bootInfoRva, int graphicsOutputGuidRva) {
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x75); code.EmitByte(0x60); // r14 = BootServices
            EmitLeaRcxRva(code, textRva, graphicsOutputGuidRva);
            code.EmitByte(0x31); code.EmitByte(0xd2); // registration = null
            EmitLeaR8Rsp(code, 120); // EFI_GRAPHICS_OUTPUT_PROTOCOL **
            // LocateProtocol follows LocateHandleBuffer at offset 304 in the
            // EFI_BOOT_SERVICES table. Its slot is therefore 312 (0x138);
            // 320 is InstallMultipleProtocolInterfaces.
            EmitBootService(code, 312); // LocateProtocol(&GOP, null, &gop)
            int failureJump = EmitFailureJump(code);

            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x74); code.EmitByte(0x24); code.EmitByte(120); // rsi = GOP
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x46); code.EmitByte(24); // rax = GOP->Mode
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x48); code.EmitByte(24); // rcx = FrameBufferBase
            EmitStoreRcxRva(code, textRva, bootInfoRva + 112);
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x48); code.EmitByte(32); // rcx = FrameBufferSize
            EmitStoreRcxRva(code, textRva, bootInfoRva + 120);
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x50); code.EmitByte(8); // rdx = Mode->Info
            code.EmitByte(0x8b); code.EmitByte(0x4a); code.EmitByte(4); // horizontal resolution
            EmitStoreEcxRva(code, textRva, bootInfoRva + 128);
            code.EmitByte(0x8b); code.EmitByte(0x4a); code.EmitByte(8); // vertical resolution
            EmitStoreEcxRva(code, textRva, bootInfoRva + 132);
            code.EmitByte(0x8b); code.EmitByte(0x4a); code.EmitByte(32); // pixels per scan line
            EmitStoreEcxRva(code, textRva, bootInfoRva + 136);
            code.EmitByte(0x8b); code.EmitByte(0x4a); code.EmitByte(12); // pixel format
            EmitStoreEcxRva(code, textRva, bootInfoRva + 140);
            return failureJump;
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
            code.EmitByte(0x83); code.EmitByte(0x7f); code.EmitByte(0x04); code.EmitByte(0x04);
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

        // Clone all present x86-64 four-level paging-structure pages into the
        // bootstrap allocator. Leaf entries retain their physical frames and
        // attributes; only table-pointer physical addresses are replaced.
        private int EmitInitializeVirtualMemory(X64Assembler code, int[] failureJumps, int failureCount) {
            code.EmitByte(0x83); code.EmitByte(0x7f); code.EmitByte(36); code.EmitByte(3);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x85); failureCount = failureCount + 1; // jne
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xff); // r15 = boot info
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x77); code.EmitByte(40); // r14 = next page
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x6f); code.EmitByte(48); // r13 = page limit
            code.EmitByte(0x4d); code.EmitByte(0x85); code.EmitByte(0xf6); // test r14, r14
            failureJumps[failureCount] = EmitConditionalJump(code, 0x84); failureCount = failureCount + 1; // jz

            // CR3 identifies the live PML4. The boot allocator already relies
            // on firmware's physical identity mapping while this copy runs.
            code.EmitByte(0x0f); code.EmitByte(0x20); code.EmitByte(0xde); // rsi = cr3
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xe6); code.Emit32(-4096);
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xf6); // test rsi, rsi
            failureJumps[failureCount] = EmitConditionalJump(code, 0x84); failureCount = failureCount + 1; // jz
            // The emitted walker has four paging levels. Do not reinterpret a
            // PML5 hierarchy as PML4/PDPT/PD/PT on firmware that enables LA57.
            code.EmitByte(0x0f); code.EmitByte(0x20); code.EmitByte(0xe0); // rax = cr4
            code.EmitByte(0xa9); code.Emit32(4096); // test CR4.LA57
            failureJumps[failureCount] = EmitConditionalJump(code, 0x85); failureCount = failureCount + 1; // jnz

            // Reserve the new PML4 root.
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xf0); // r8 = r14
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xc6); code.Emit32(4096); // r14 += page
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xc6); // cmp r14, r8
            failureJumps[failureCount] = EmitConditionalJump(code, 0x86); failureCount = failureCount + 1; // jbe overflow
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xee); // cmp r14, r13
            failureJumps[failureCount] = EmitConditionalJump(code, 0x87); failureCount = failureCount + 1; // ja exhausted
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xc4); // r12 = r8
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xc7); // rdi = r8
            code.EmitByte(0xb9); code.Emit32(512);
            code.EmitByte(0xfc); // cld
            code.EmitByte(0xf3); code.EmitByte(0x48); code.EmitByte(0xa5); // rep movsq

            // RBX walks the copied PML4. R9 is its exclusive end address.
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xe3); // rbx = r12
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xe1); // r9 = r12
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xc1); code.Emit32(4096);
            int pml4Start = code.Position();
            code.EmitByte(0x4c); code.EmitByte(0x39); code.EmitByte(0xcb); // cmp rbx, r9
            int pml4Complete = EmitConditionalJump(code, 0x83); // jae
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x03); // rax = [rbx]
            code.EmitByte(0xa8); code.EmitByte(1); // test al, present
            int pml4Absent = EmitConditionalJump(code, 0x84); // jz

            // Split the PML4 entry into its source-table address (RSI) and
            // flags (RDX), preserving even high attribute bits such as NX.
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc6); // rsi = rax
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe6); code.EmitByte(12);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xee); code.EmitByte(12);
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xe6); code.Emit32(-4096);
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc2); // rdx = rax
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe8); code.EmitByte(52);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe0); code.EmitByte(52);
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xe2); code.Emit32(4095);
            code.EmitByte(0x48); code.EmitByte(0x09); code.EmitByte(0xc2); // rdx = entry flags

            // Allocate and copy the child PDPT, then update the copied PML4.
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xf0); // r8 = r14
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xc6); code.Emit32(4096);
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xc6);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x86); failureCount = failureCount + 1; // jbe overflow
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xee);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x87); failureCount = failureCount + 1; // ja exhausted
            code.EmitByte(0x4c); code.EmitByte(0x09); code.EmitByte(0xc2); // rdx |= r8
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x13); // [rbx] = rdx
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xc7); // rdi = r8
            code.EmitByte(0xb9); code.Emit32(512);
            code.EmitByte(0xfc); code.EmitByte(0xf3); code.EmitByte(0x48); code.EmitByte(0xa5);
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xc5); // rbp = r8
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xc2); // r10 = r8
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xc2); code.Emit32(4096);
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0x54); code.EmitByte(0x24); code.EmitByte(0); // [rsp] = r10

            int pdptStart = code.Position();
            code.EmitByte(0x48); code.EmitByte(0x3b); code.EmitByte(0x6c); code.EmitByte(0x24); code.EmitByte(0); // cmp rbp, [rsp]
            int pdptComplete = EmitConditionalJump(code, 0x83); // jae
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x45); code.EmitByte(0); // rax = [rbp]
            code.EmitByte(0xa8); code.EmitByte(1);
            int pdptAbsent = EmitConditionalJump(code, 0x84); // jz
            code.EmitByte(0xa8); code.EmitByte(0x80); // test page-size bit
            int pdptLeaf = EmitConditionalJump(code, 0x85); // jnz: 1 GiB leaf

            // Clone a PD referenced by this PDPT entry.
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc6);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe6); code.EmitByte(12);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xee); code.EmitByte(12);
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xe6); code.Emit32(-4096);
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc2);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe8); code.EmitByte(52);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe0); code.EmitByte(52);
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xe2); code.Emit32(4095);
            code.EmitByte(0x48); code.EmitByte(0x09); code.EmitByte(0xc2);
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xf0);
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xc6); code.Emit32(4096);
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xc6);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x86); failureCount = failureCount + 1; // jbe overflow
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xee);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x87); failureCount = failureCount + 1; // ja exhausted
            code.EmitByte(0x4c); code.EmitByte(0x09); code.EmitByte(0xc2);
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x55); code.EmitByte(0); // [rbp] = rdx
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xc7);
            code.EmitByte(0xb9); code.Emit32(512);
            code.EmitByte(0xfc); code.EmitByte(0xf3); code.EmitByte(0x48); code.EmitByte(0xa5);
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xc3); // r11 = r8
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xc2); // r10 = r8
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xc2); code.Emit32(4096);
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0x54); code.EmitByte(0x24); code.EmitByte(8); // [rsp + 8] = r10

            int pdStart = code.Position();
            code.EmitByte(0x4c); code.EmitByte(0x3b); code.EmitByte(0x5c); code.EmitByte(0x24); code.EmitByte(8); // cmp r11, [rsp + 8]
            int pdComplete = EmitConditionalJump(code, 0x83); // jae
            code.EmitByte(0x49); code.EmitByte(0x8b); code.EmitByte(0x03); // rax = [r11]
            code.EmitByte(0xa8); code.EmitByte(1);
            int pdAbsent = EmitConditionalJump(code, 0x84); // jz
            code.EmitByte(0xa8); code.EmitByte(0x80);
            int pdLeaf = EmitConditionalJump(code, 0x85); // jnz: 2 MiB leaf

            // Clone the PT that backs a non-large PD entry.
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc6);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe6); code.EmitByte(12);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xee); code.EmitByte(12);
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xe6); code.Emit32(-4096);
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc2);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe8); code.EmitByte(52);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe0); code.EmitByte(52);
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xe2); code.Emit32(4095);
            code.EmitByte(0x48); code.EmitByte(0x09); code.EmitByte(0xc2);
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xf0);
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xc6); code.Emit32(4096);
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xc6);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x86); failureCount = failureCount + 1; // jbe overflow
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xee);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x87); failureCount = failureCount + 1; // ja exhausted
            code.EmitByte(0x4c); code.EmitByte(0x09); code.EmitByte(0xc2);
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0x13); // [r11] = rdx
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xc7);
            code.EmitByte(0xb9); code.Emit32(512);
            code.EmitByte(0xfc); code.EmitByte(0xf3); code.EmitByte(0x48); code.EmitByte(0xa5);

            int pdAdvance = code.Position();
            code.Patch32(pdAbsent, pdAdvance - (pdAbsent + 4));
            code.Patch32(pdLeaf, pdAdvance - (pdLeaf + 4));
            code.EmitByte(0x49); code.EmitByte(0x83); code.EmitByte(0xc3); code.EmitByte(8); // r11 += entry
            EmitJumpTo(code, pdStart);

            int pdptAdvance = code.Position();
            code.Patch32(pdComplete, pdptAdvance - (pdComplete + 4));
            code.Patch32(pdptAbsent, pdptAdvance - (pdptAbsent + 4));
            code.Patch32(pdptLeaf, pdptAdvance - (pdptLeaf + 4));
            code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xc5); code.EmitByte(8); // rbp += entry
            EmitJumpTo(code, pdptStart);

            int pml4Advance = code.Position();
            code.Patch32(pdptComplete, pml4Advance - (pdptComplete + 4));
            code.Patch32(pml4Absent, pml4Advance - (pml4Absent + 4));
            code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xc3); code.EmitByte(8); // rbx += entry
            EmitJumpTo(code, pml4Start);

            int pagingHierarchyComplete = code.Position();
            code.Patch32(pml4Complete, pagingHierarchyComplete - (pml4Complete + 4));

            // Activate the allocator-owned hierarchy only after it is complete.
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0x77); code.EmitByte(40); // next page = r14
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0x67); code.EmitByte(64); // PML4 root = r12
            code.EmitByte(0x41); code.EmitByte(0x0f); code.EmitByte(0x22); code.EmitByte(0xdc); // cr3 = r12
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xff); // rdi = r15
            code.EmitByte(0xc7); code.EmitByte(0x47); code.EmitByte(36); code.Emit32(15);
            return failureCount;
        }

        // Establish the initial kernel mapping policy: virtual page zero is
        // always unmapped. If firmware used a large mapping at that address,
        // split only that leaf before removing its first 4 KiB page.
        private int EmitApplyKernelMappingPolicy(X64Assembler code, int[] failureJumps, int failureCount) {
            code.EmitByte(0x83); code.EmitByte(0x7f); code.EmitByte(36); code.EmitByte(15);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x85); failureCount = failureCount + 1; // jne
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xff); // r15 = boot info
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x77); code.EmitByte(40); // r14 = next page
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x6f); code.EmitByte(48); // r13 = limit
            code.EmitByte(0x49); code.EmitByte(0x8b); code.EmitByte(0x5f); code.EmitByte(64); // rbx = PML4
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xdb);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x84); failureCount = failureCount + 1; // jz

            // Follow index zero at each level. An absent entry already supplies
            // the required null-page guard.
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x03); // rax = PML4[0]
            code.EmitByte(0xa8); code.EmitByte(1);
            int pml4Absent = EmitConditionalJump(code, 0x84); // jz
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc6); // rsi = PDPT
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe6); code.EmitByte(12);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xee); code.EmitByte(12);
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xe6); code.Emit32(-4096);
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x06); // rax = PDPT[0]
            code.EmitByte(0xa8); code.EmitByte(1);
            int pdptAbsent = EmitConditionalJump(code, 0x84); // jz
            code.EmitByte(0xa8); code.EmitByte(0x80);
            int pdptLarge = EmitConditionalJump(code, 0x85); // jnz

            // PDPT[0] already points at a PD.
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc5); // rbp = PD
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe5); code.EmitByte(12);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xed); code.EmitByte(12);
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xe5); code.Emit32(-4096);
            code.EmitByte(0xe9);
            int normalPdptReady = code.Position();
            code.Emit32(0);

            // Split a 1 GiB PDPT leaf into a PD of equivalent 2 MiB leaves.
            int pdptLargeStart = code.Position();
            code.Patch32(pdptLarge, pdptLargeStart - (pdptLarge + 4));
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc3); // rbx = leaf physical base
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe3); code.EmitByte(12);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xeb); code.EmitByte(12);
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xe3); code.Emit32(-4096);
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xc2); // r10 = original leaf entry
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xc3); // r11 = leaf flags
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe8); code.EmitByte(52);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe0); code.EmitByte(52);
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xe3); code.Emit32(4095);
            code.EmitByte(0x49); code.EmitByte(0x09); code.EmitByte(0xc3);
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xdc); // r12 = parent flags
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xe4); code.Emit32(-129);
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xe2); code.Emit32(4096);
            code.EmitByte(0x4d); code.EmitByte(0x85); code.EmitByte(0xd2);
            int noOneGiBPat = EmitConditionalJump(code, 0x84); // jz
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xcb); code.Emit32(4096);
            int oneGiBPatDone = code.Position();
            code.Patch32(noOneGiBPat, oneGiBPatDone - (noOneGiBPat + 4));
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xf0); // r8 = r14
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xc6); code.Emit32(4096);
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xc6);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x86); failureCount = failureCount + 1; // jbe
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xee);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x87); failureCount = failureCount + 1; // ja
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xe2); // rdx = r12
            code.EmitByte(0x4c); code.EmitByte(0x09); code.EmitByte(0xc2);
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x16); // PDPT[0] = new PD
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xc7); // rdi = new PD
            code.EmitByte(0xb9); code.Emit32(512);
            int pdeFillStart = code.Position();
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xd8);
            code.EmitByte(0x4c); code.EmitByte(0x09); code.EmitByte(0xd8);
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x07);
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xc3); code.Emit32(2097152);
            code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xc7); code.EmitByte(8);
            code.EmitByte(0x48); code.EmitByte(0xff); code.EmitByte(0xc9);
            int pdeFillAgain = EmitConditionalJump(code, 0x85); // jnz
            code.Patch32(pdeFillAgain, pdeFillStart - (pdeFillAgain + 4));
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xc5); // rbp = new PD

            int pdCheck = code.Position();
            code.Patch32(normalPdptReady, pdCheck - (normalPdptReady + 4));
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x45); code.EmitByte(0); // rax = PD[0]
            code.EmitByte(0xa8); code.EmitByte(1);
            int pdAbsent = EmitConditionalJump(code, 0x84); // jz
            code.EmitByte(0xa8); code.EmitByte(0x80);
            int pdLarge = EmitConditionalJump(code, 0x85); // jnz

            // A normal PT can have its null leaf removed directly.
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc6); // rsi = PT
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe6); code.EmitByte(12);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xee); code.EmitByte(12);
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xe6); code.Emit32(-4096);
            code.EmitByte(0x48); code.EmitByte(0xc7); code.EmitByte(0x06); code.Emit32(0); // PT[0] = 0
            code.EmitByte(0xe9);
            int normalPtReady = code.Position();
            code.Emit32(0);

            // Split a 2 MiB PD leaf into a PT, preserving the PAT attribute
            // while converting its large-page PS bit into the PTE PAT bit.
            int pdLargeStart = code.Position();
            code.Patch32(pdLarge, pdLargeStart - (pdLarge + 4));
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc3); // rbx = leaf physical base
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe3); code.EmitByte(12);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xeb); code.EmitByte(12);
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xe3); code.Emit32(-4096);
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xc2); // r10 = original leaf entry
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xc3); // r11 = leaf flags
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe8); code.EmitByte(52);
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe0); code.EmitByte(52);
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xe3); code.Emit32(4095);
            code.EmitByte(0x49); code.EmitByte(0x09); code.EmitByte(0xc3);
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xdc); // r12 = parent flags
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xe4); code.Emit32(-129);
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xe3); code.Emit32(-129); // clear PS for PTE
            // The original large-page PAT bit is bit 12. It becomes PTE bit 7.
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xe2); code.Emit32(4096);
            code.EmitByte(0x4d); code.EmitByte(0x85); code.EmitByte(0xd2);
            int noLargePat = EmitConditionalJump(code, 0x84); // jz
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xcb); code.Emit32(128);
            int largePatDone = code.Position();
            code.Patch32(noLargePat, largePatDone - (noLargePat + 4));
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xf0); // r8 = r14
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xc6); code.Emit32(4096);
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xc6);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x86); failureCount = failureCount + 1; // jbe
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xee);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x87); failureCount = failureCount + 1; // ja
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xe2); // rdx = r12
            code.EmitByte(0x4c); code.EmitByte(0x09); code.EmitByte(0xc2);
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x55); code.EmitByte(0); // PD[0] = new PT
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xc7); // rdi = new PT
            code.EmitByte(0xb9); code.Emit32(512);
            int pteFillStart = code.Position();
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xd8);
            code.EmitByte(0x4c); code.EmitByte(0x09); code.EmitByte(0xd8);
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x07);
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xc3); code.Emit32(4096);
            code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xc7); code.EmitByte(8);
            code.EmitByte(0x48); code.EmitByte(0xff); code.EmitByte(0xc9);
            int pteFillAgain = EmitConditionalJump(code, 0x85); // jnz
            code.Patch32(pteFillAgain, pteFillStart - (pteFillAgain + 4));
            code.EmitByte(0x49); code.EmitByte(0xc7); code.EmitByte(0x00); code.Emit32(0); // PT[0] = 0

            int policyComplete = code.Position();
            code.Patch32(pml4Absent, policyComplete - (pml4Absent + 4));
            code.Patch32(pdptAbsent, policyComplete - (pdptAbsent + 4));
            code.Patch32(pdAbsent, policyComplete - (pdAbsent + 4));
            code.Patch32(normalPtReady, policyComplete - (normalPtReady + 4));
            // CR3 is already active. Discard a possible cached translation for
            // the page whose PTE was just removed before publishing the policy.
            code.EmitByte(0x31); code.EmitByte(0xc0); // rax = 0
            code.EmitByte(0x0f); code.EmitByte(0x01); code.EmitByte(0x38); // invlpg [rax]
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0x77); code.EmitByte(40); // next page = r14
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xff); // rdi = r15
            code.EmitByte(0xc7); code.EmitByte(0x47); code.EmitByte(36); code.Emit32(31);
            return failureCount;
        }

        // Allocate and zero one physical page. The selected physical address is
        // returned in RAX and recorded at KernelBootInfo + 72 for later stages.
        private int EmitAllocateKernelPage(X64Assembler code, int[] failureJumps, int failureCount) {
            code.EmitByte(0x83); code.EmitByte(0x7f); code.EmitByte(36); code.EmitByte(31);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x85); failureCount = failureCount + 1; // jne
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xff); // r15 = boot info
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x77); code.EmitByte(40); // r14 = next
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x6f); code.EmitByte(48); // r13 = limit
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xf0); // r8 = r14
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xc6); code.Emit32(4096);
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xc6);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x86); failureCount = failureCount + 1; // jbe
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xee);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x87); failureCount = failureCount + 1; // ja
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xc7); // rdi = page
            code.EmitByte(0x31); code.EmitByte(0xc0);
            code.EmitByte(0xb9); code.Emit32(512);
            code.EmitByte(0xfc); code.EmitByte(0xf3); code.EmitByte(0x48); code.EmitByte(0xab); // rep stosq
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0x77); code.EmitByte(40); // next = r14
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0x47); code.EmitByte(72); // last allocation = r8
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xc0); // rax = r8
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xff); // rdi = r15
            return failureCount;
        }

        // The initial heap page comes from the physical allocator. The heap is
        // a zero-filled, 16-byte aligned bump range; BootInfo records enough
        // state for later kernel code to inspect its base, cursor, and limit.
        private int EmitInitializeKernelHeap(X64Assembler code, int[] failureJumps, int failureCount) {
            failureCount = EmitAllocateKernelPage(code, failureJumps, failureCount);
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xc0); // r8 = first heap page
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0x47); code.EmitByte(80); // heap base
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0x47); code.EmitByte(88); // heap next
            code.EmitByte(0x4d); code.EmitByte(0x8d); code.EmitByte(0x88); code.Emit32(4096); // r9 = heap limit
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0x4f); code.EmitByte(96);
            code.EmitByte(0x49); code.EmitByte(0xc7); code.EmitByte(0x47); code.EmitByte(104); code.Emit32(0); // no allocation yet
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xff); // rdi = boot info
            code.EmitByte(0xc7); code.EmitByte(0x47); code.EmitByte(36); code.Emit32(63);
            return failureCount;
        }

        // Allocate a literal number of bytes from the bump heap. The heap only
        // grows by contiguous physical pages, which preserves a single virtual
        // range in the identity mappings retained at handoff.
        private int EmitAllocateKernelHeap(X64Assembler code, int byteCount, int[] failureJumps, int failureCount) {
            int alignedByteCount = ((byteCount + 15) / 16) * 16;
            code.EmitByte(0x83); code.EmitByte(0x7f); code.EmitByte(36); code.EmitByte(63);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x85); failureCount = failureCount + 1; // jne
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xff); // r15 = boot info
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x47); code.EmitByte(88); // r8 = allocation start
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xc1); // r9 = requested end
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xc1); code.Emit32(alignedByteCount);
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xc1); // cmp r9, r8
            failureJumps[failureCount] = EmitConditionalJump(code, 0x86); failureCount = failureCount + 1; // jbe overflow
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x57); code.EmitByte(96); // r10 = heap limit

            int growHeap = code.Position();
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xca); // cmp r10, r9
            int heapCapacityReady = EmitConditionalJump(code, 0x83); // jae

            // Reserve, clear, and append one contiguous physical page.
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x77); code.EmitByte(40); // r14 = physical next
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x6f); code.EmitByte(48); // r13 = physical limit
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0xf3); // r11 = physical page
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xc6); code.Emit32(4096);
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xde);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x86); failureCount = failureCount + 1; // jbe overflow
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xee);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x87); failureCount = failureCount + 1; // ja exhausted
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xdf); // rdi = physical page
            code.EmitByte(0x31); code.EmitByte(0xc0);
            code.EmitByte(0xb9); code.Emit32(512);
            code.EmitByte(0xfc); code.EmitByte(0xf3); code.EmitByte(0x48); code.EmitByte(0xab); // rep stosq
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0x77); code.EmitByte(40); // physical next
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0x5f); code.EmitByte(72); // last physical page
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xd3); // cmp r11, r10
            failureJumps[failureCount] = EmitConditionalJump(code, 0x85); failureCount = failureCount + 1; // jne non-contiguous page
            code.EmitByte(0x49); code.EmitByte(0x81); code.EmitByte(0xc2); code.Emit32(4096);
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xda); // cmp r10, r11
            failureJumps[failureCount] = EmitConditionalJump(code, 0x86); failureCount = failureCount + 1; // jbe overflow
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0x57); code.EmitByte(96); // heap limit
            EmitJumpTo(code, growHeap);

            int allocationReady = code.Position();
            code.Patch32(heapCapacityReady, allocationReady - (heapCapacityReady + 4));
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0x47); code.EmitByte(104); // last heap allocation = r8
            code.EmitByte(0x4d); code.EmitByte(0x89); code.EmitByte(0x4f); code.EmitByte(88); // heap next = r9
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xc0); // rax = allocation start
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xff); // rdi = boot info
            return failureCount;
        }

        // A firmware-independent console starts from the GOP values captured
        // before ExitBootServices. We accept the two standard 32-bit GOP pixel
        // formats; white and black have the same channel values in either
        // ordering. Geometry is bounded before calculating the clear range.
        private int EmitInitializeFramebuffer(X64Assembler code, int[] failureJumps, int failureCount) {
            code.EmitByte(0x83); code.EmitByte(0x7f); code.EmitByte(36); code.EmitByte(63);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x85); failureCount = failureCount + 1; // jne
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xff); // r15 = BootInfo
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x47); code.EmitByte(112); // r8 = framebuffer base
            code.EmitByte(0x4d); code.EmitByte(0x85); code.EmitByte(0xc0);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x84); failureCount = failureCount + 1; // jz
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x4f); code.EmitByte(120); // r9 = framebuffer size
            code.EmitByte(0x4d); code.EmitByte(0x85); code.EmitByte(0xc9);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x84); failureCount = failureCount + 1; // jz
            code.EmitByte(0x41); code.EmitByte(0x8b); code.EmitByte(0x87); code.Emit32(140); // eax = pixel format
            code.EmitByte(0x83); code.EmitByte(0xf8); code.EmitByte(1);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x87); failureCount = failureCount + 1; // ja
            code.EmitByte(0x41); code.EmitByte(0x8b); code.EmitByte(0x9f); code.Emit32(128); // ebx = width
            code.EmitByte(0x83); code.EmitByte(0xfb); code.EmitByte(8);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x82); failureCount = failureCount + 1; // jb
            code.EmitByte(0x41); code.EmitByte(0x8b); code.EmitByte(0x97); code.Emit32(132); // edx = height
            code.EmitByte(0x83); code.EmitByte(0xfa); code.EmitByte(8);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x82); failureCount = failureCount + 1; // jb
            code.EmitByte(0x41); code.EmitByte(0x8b); code.EmitByte(0x8f); code.Emit32(136); // ecx = pixels per scan line
            code.EmitByte(0x39); code.EmitByte(0xd9); // cmp ecx, ebx
            failureJumps[failureCount] = EmitConditionalJump(code, 0x82); failureCount = failureCount + 1; // jb
            code.EmitByte(0x81); code.EmitByte(0xf9); code.Emit32(16384);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x87); failureCount = failureCount + 1; // ja
            code.EmitByte(0x81); code.EmitByte(0xfa); code.Emit32(16384);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x87); failureCount = failureCount + 1; // ja
            code.EmitByte(0x41); code.EmitByte(0x89); code.EmitByte(0xca); // r10d = ecx
            code.EmitByte(0x4c); code.EmitByte(0x0f); code.EmitByte(0xaf); code.EmitByte(0xd2); // r10 *= rdx
            code.EmitByte(0x49); code.EmitByte(0xc1); code.EmitByte(0xe2); code.EmitByte(2); // byte count
            code.EmitByte(0x4d); code.EmitByte(0x39); code.EmitByte(0xca); // cmp r10, r9
            failureJumps[failureCount] = EmitConditionalJump(code, 0x87); failureCount = failureCount + 1; // ja
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xc7); // rdi = framebuffer
            code.EmitByte(0x31); code.EmitByte(0xc0);
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xd1); // rcx = byte count
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe9); code.EmitByte(2); // dword count
            code.EmitByte(0xfc); code.EmitByte(0xf3); code.EmitByte(0xab); // cld; rep stosd
            code.EmitByte(0x41); code.EmitByte(0xc7); code.EmitByte(0x87); code.Emit32(144); code.Emit32(0); // cursor x
            code.EmitByte(0x41); code.EmitByte(0xc7); code.EmitByte(0x87); code.Emit32(148); code.Emit32(0); // cursor y
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xff); // rdi = BootInfo
            code.EmitByte(0xc7); code.EmitByte(0x47); code.EmitByte(36); code.Emit32(127);
            return failureCount;
        }

        // Render one NUL-terminated ASCII literal using the 8x8 bitmap stored
        // in .rdata. A line wraps at the reported horizontal resolution. When
        // the cursor reaches the bottom, it wraps to the first row; scrolling
        // can be added after a general memory move primitive exists.
        private int EmitFramebufferWriteLine(X64Assembler code, int textRva, int bootInfoRva, int fontRva, int messageRva, int[] failureJumps, int failureCount) {
            code.EmitByte(0x83); code.EmitByte(0x7f); code.EmitByte(36); code.EmitByte(127);
            failureJumps[failureCount] = EmitConditionalJump(code, 0x85); failureCount = failureCount + 1; // jne
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xff); // r15 = BootInfo
            code.EmitByte(0x4d); code.EmitByte(0x8b); code.EmitByte(0x47); code.EmitByte(112); // r8 = framebuffer
            EmitLeaR9Rva(code, textRva, fontRva);
            EmitLeaR10Rva(code, textRva, messageRva);
            code.EmitByte(0x45); code.EmitByte(0x8b); code.EmitByte(0x9f); code.Emit32(144); // r11d = cursor x
            code.EmitByte(0x45); code.EmitByte(0x8b); code.EmitByte(0xa7); code.Emit32(148); // r12d = cursor y
            code.EmitByte(0x41); code.EmitByte(0x8b); code.EmitByte(0x9f); code.Emit32(128); // ebx = width
            code.EmitByte(0x41); code.EmitByte(0x8b); code.EmitByte(0xaf); code.Emit32(132); // ebp = height
            code.EmitByte(0x45); code.EmitByte(0x8b); code.EmitByte(0xaf); code.Emit32(136); // r13d = stride pixels
            code.EmitByte(0x49); code.EmitByte(0xc1); code.EmitByte(0xe5); code.EmitByte(2); // r13 = stride bytes

            int characterLoop = code.Position();
            code.EmitByte(0x41); code.EmitByte(0x0f); code.EmitByte(0xb6); code.EmitByte(0x02); // eax = *message
            code.EmitByte(0x84); code.EmitByte(0xc0);
            int endLine = EmitConditionalJump(code, 0x84); // jz
            code.EmitByte(0x49); code.EmitByte(0xff); code.EmitByte(0xc2); // message++
            code.EmitByte(0x2c); code.EmitByte(32); // normalize printable ASCII to font index
            code.EmitByte(0x3c); code.EmitByte(94);
            int glyphReady = EmitConditionalJump(code, 0x86); // jbe
            code.EmitByte(0xb0); code.EmitByte(31); // fallback '?'
            int glyphReadyAt = code.Position();
            code.Patch32(glyphReady, glyphReadyAt - (glyphReady + 4));
            code.EmitByte(0x0f); code.EmitByte(0xb6); code.EmitByte(0xc0);
            code.EmitByte(0xc1); code.EmitByte(0xe0); code.EmitByte(3);
            code.EmitByte(0x4d); code.EmitByte(0x8d); code.EmitByte(0x34); code.EmitByte(0x01); // r14 = glyph
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xd8); // rax = cursor x
            code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xc0); code.EmitByte(8);
            code.EmitByte(0x48); code.EmitByte(0x39); code.EmitByte(0xd8); // cmp rax, rbx
            int xReady = EmitConditionalJump(code, 0x86); // jbe
            code.EmitByte(0x45); code.EmitByte(0x31); code.EmitByte(0xdb); // cursor x = 0
            code.EmitByte(0x41); code.EmitByte(0x83); code.EmitByte(0xc4); code.EmitByte(8); // cursor y += 8
            int xReadyAt = code.Position();
            code.Patch32(xReady, xReadyAt - (xReady + 4));
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xe0); // rax = cursor y
            code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xc0); code.EmitByte(8);
            code.EmitByte(0x48); code.EmitByte(0x39); code.EmitByte(0xe8); // cmp rax, rbp
            int yReady = EmitConditionalJump(code, 0x86); // jbe
            code.EmitByte(0x45); code.EmitByte(0x31); code.EmitByte(0xe4); // cursor y = 0
            int yReadyAt = code.Position();
            code.Patch32(yReady, yReadyAt - (yReady + 4));
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xe0); // rax = cursor y
            code.EmitByte(0x49); code.EmitByte(0x0f); code.EmitByte(0xaf); code.EmitByte(0xc5); // y * stride
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xda); // rdx = cursor x
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe2); code.EmitByte(2);
            code.EmitByte(0x48); code.EmitByte(0x01); code.EmitByte(0xd0);
            code.EmitByte(0x4c); code.EmitByte(0x01); code.EmitByte(0xc0); // rax = pixel address
            code.EmitByte(0xb9); code.Emit32(8); // eight glyph rows

            int rowLoop = code.Position();
            code.EmitByte(0x41); code.EmitByte(0x0f); code.EmitByte(0xb6); code.EmitByte(0x16); // edx = glyph row
            code.EmitByte(0x49); code.EmitByte(0xff); code.EmitByte(0xc6);
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc6); // rsi = row address
            code.EmitByte(0xbf); code.Emit32(8); // eight glyph columns
            int pixelLoop = code.Position();
            code.EmitByte(0xf6); code.EmitByte(0xc2); code.EmitByte(128);
            int blackPixel = EmitConditionalJump(code, 0x84); // jz
            code.EmitByte(0xc7); code.EmitByte(0x06); code.Emit32(16777215); // white
            int pixelDone = EmitForwardJump(code);
            int blackPixelAt = code.Position();
            code.Patch32(blackPixel, blackPixelAt - (blackPixel + 4));
            code.EmitByte(0xc7); code.EmitByte(0x06); code.Emit32(0); // black
            int pixelDoneAt = code.Position();
            code.Patch32(pixelDone, pixelDoneAt - (pixelDone + 4));
            code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xc6); code.EmitByte(4);
            code.EmitByte(0xd0); code.EmitByte(0xe2); // next glyph bit
            code.EmitByte(0xff); code.EmitByte(0xcf);
            int nextPixel = EmitConditionalJump(code, 0x85); // jnz
            code.Patch32(nextPixel, pixelLoop - (nextPixel + 4));
            code.EmitByte(0x4c); code.EmitByte(0x01); code.EmitByte(0xe8); // next screen row
            code.EmitByte(0xff); code.EmitByte(0xc9);
            int nextRow = EmitConditionalJump(code, 0x85); // jnz
            code.Patch32(nextRow, rowLoop - (nextRow + 4));
            code.EmitByte(0x49); code.EmitByte(0x83); code.EmitByte(0xc3); code.EmitByte(8); // cursor x += 8
            EmitJumpTo(code, characterLoop);

            int endLineAt = code.Position();
            code.Patch32(endLine, endLineAt - (endLine + 4));
            code.EmitByte(0x45); code.EmitByte(0x31); code.EmitByte(0xdb); // next line, x = 0
            code.EmitByte(0x41); code.EmitByte(0x83); code.EmitByte(0xc4); code.EmitByte(8);
            code.EmitByte(0x49); code.EmitByte(0x39); code.EmitByte(0xec); // cmp r12, rbp
            int saveCursor = EmitConditionalJump(code, 0x82); // jb
            code.EmitByte(0x45); code.EmitByte(0x31); code.EmitByte(0xe4); // wrap to top
            int saveCursorAt = code.Position();
            code.Patch32(saveCursor, saveCursorAt - (saveCursor + 4));
            code.EmitByte(0x45); code.EmitByte(0x89); code.EmitByte(0x9f); code.Emit32(144);
            code.EmitByte(0x45); code.EmitByte(0x89); code.EmitByte(0xa7); code.Emit32(148);
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xff); // rdi = BootInfo
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

        private int EmitForwardJump(X64Assembler code) {
            code.EmitByte(0xe9);
            int patch = code.Position();
            code.Emit32(0);
            return patch;
        }

        private void EmitLeaRcxRva(X64Assembler code, int textRva, int targetRva) {
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x0d);
            code.Emit32(targetRva - (textRva + code.Position() + 4));
        }

        private void EmitLeaRdxRva(X64Assembler code, int textRva, int targetRva) {
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x15);
            code.Emit32(targetRva - (textRva + code.Position() + 4));
        }

        private void EmitStoreRaxRva(X64Assembler code, int textRva, int targetRva) {
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x05);
            code.Emit32(targetRva - (textRva + code.Position() + 4));
        }

        private void EmitStoreRcxRva(X64Assembler code, int textRva, int targetRva) {
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x0d);
            code.Emit32(targetRva - (textRva + code.Position() + 4));
        }

        private void EmitStoreEcxRva(X64Assembler code, int textRva, int targetRva) {
            code.EmitByte(0x89); code.EmitByte(0x0d);
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

        private void EmitLeaR9Rva(X64Assembler code, int textRva, int targetRva) {
            code.EmitByte(0x4c); code.EmitByte(0x8d); code.EmitByte(0x0d);
            code.Emit32(targetRva - (textRva + code.Position() + 4));
        }

        private void EmitLeaR10Rva(X64Assembler code, int textRva, int targetRva) {
            code.EmitByte(0x4c); code.EmitByte(0x8d); code.EmitByte(0x15);
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

        private void WriteAscii(byte[] image, int offset, string text, ElfImageBuilder ascii) {
            int i = 0;
            while (i < text.Length) {
                image[offset + i] = (byte)ascii.AsciiCode(text[i]);
                i = i + 1;
            }
            image[offset + text.Length] = (byte)0;
        }

        // KernelBootInfo: magic "AUBI", ABI version, EFI memory-map pointer,
        // byte size, descriptor size, descriptor version, state flags, then
        // physical-page next, limit, metadata-page, active PML4, physical-page
        // allocation, heap range/allocation addresses, and framebuffer data
        // captured before firmware services are released.
        private void WriteKernelBootInfo(byte[] image, int offset) {
            Write32(image, offset, 1229083969); // "AUBI" in little-endian order
            Write32(image, offset + 4, 4);
        }

        private void WriteGraphicsOutputGuid(byte[] image, int offset) {
            int[] bytes = new int[16];
            bytes[0] = 222; bytes[1] = 169; bytes[2] = 66; bytes[3] = 144; bytes[4] = 220; bytes[5] = 35; bytes[6] = 56; bytes[7] = 74;
            bytes[8] = 150; bytes[9] = 251; bytes[10] = 122; bytes[11] = 222; bytes[12] = 208; bytes[13] = 128; bytes[14] = 81; bytes[15] = 106;
            WriteGuid(image, offset, bytes);
        }

        // Printable ASCII (U+0020 through U+007E), eight one-bit rows per
        // glyph. The table is included in every framebuffer kernel image.
        private void WriteFramebufferFont(byte[] image, int offset) {
            Write32(image, offset + 0, 0);
            Write32(image, offset + 4, 0);
            Write32(image, offset + 8, 406600728);
            Write32(image, offset + 12, 1572888);
            Write32(image, offset + 16, 2385510);
            Write32(image, offset + 20, 0);
            Write32(image, offset + 24, 1828613228);
            Write32(image, offset + 28, 7105790);
            Write32(image, offset + 32, 1012940312);
            Write32(image, offset + 36, 1604614);
            Write32(image, offset + 40, 416073216);
            Write32(image, offset + 44, 13002288);
            Write32(image, offset + 48, 1983409208);
            Write32(image, offset + 52, 7785692);
            Write32(image, offset + 56, 3151896);
            Write32(image, offset + 60, 0);
            Write32(image, offset + 64, 808458252);
            Write32(image, offset + 68, 792624);
            Write32(image, offset + 72, 202119216);
            Write32(image, offset + 76, 3151884);
            Write32(image, offset + 80, -12818944);
            Write32(image, offset + 84, 26172);
            Write32(image, offset + 88, 2115508224);
            Write32(image, offset + 92, 6168);
            Write32(image, offset + 96, 0);
            Write32(image, offset + 100, 806885376);
            Write32(image, offset + 104, 2113929216);
            Write32(image, offset + 108, 0);
            Write32(image, offset + 112, 0);
            Write32(image, offset + 116, 1579008);
            Write32(image, offset + 120, 806882310);
            Write32(image, offset + 124, 8437856);
            Write32(image, offset + 128, -691639240);
            Write32(image, offset + 132, 3697862);
            Write32(image, offset + 136, 404240408);
            Write32(image, offset + 140, 8263704);
            Write32(image, offset + 144, 470206076);
            Write32(image, offset + 148, 16672304);
            Write32(image, offset + 152, 1007076988);
            Write32(image, offset + 156, 8177158);
            Write32(image, offset + 160, -865321956);
            Write32(image, offset + 164, 1969406);
            Write32(image, offset + 168, -54476546);
            Write32(image, offset + 172, 8177158);
            Write32(image, offset + 176, -54501320);
            Write32(image, offset + 180, 8177350);
            Write32(image, offset + 184, 403490558);
            Write32(image, offset + 188, 3158064);
            Write32(image, offset + 192, 2093401724);
            Write32(image, offset + 196, 8177350);
            Write32(image, offset + 200, 2126956156);
            Write32(image, offset + 204, 7867398);
            Write32(image, offset + 208, 1579008);
            Write32(image, offset + 212, 1579008);
            Write32(image, offset + 216, 1579008);
            Write32(image, offset + 220, 806885376);
            Write32(image, offset + 224, 806882310);
            Write32(image, offset + 228, 396312);
            Write32(image, offset + 232, 8257536);
            Write32(image, offset + 236, 32256);
            Write32(image, offset + 240, 202911840);
            Write32(image, offset + 244, 6303768);
            Write32(image, offset + 248, 403490428);
            Write32(image, offset + 252, 1572888);
            Write32(image, offset + 256, -555825540);
            Write32(image, offset + 260, 7913694);
            Write32(image, offset + 264, -20550600);
            Write32(image, offset + 268, 13027014);
            Write32(image, offset + 272, 2087085820);
            Write32(image, offset + 276, 16541286);
            Write32(image, offset + 280, -1061132740);
            Write32(image, offset + 284, 3958464);
            Write32(image, offset + 288, 1717988600);
            Write32(image, offset + 292, 16280678);
            Write32(image, offset + 296, 2020107006);
            Write32(image, offset + 300, 16671336);
            Write32(image, offset + 304, 2020107006);
            Write32(image, offset + 308, 15753320);
            Write32(image, offset + 312, -1061132740);
            Write32(image, offset + 316, 3827406);
            Write32(image, offset + 320, -20527418);
            Write32(image, offset + 324, 13027014);
            Write32(image, offset + 328, 404232252);
            Write32(image, offset + 332, 3938328);
            Write32(image, offset + 336, 202116126);
            Write32(image, offset + 340, 7916748);
            Write32(image, offset + 344, 2020370150);
            Write32(image, offset + 348, 15099500);
            Write32(image, offset + 352, 1616929008);
            Write32(image, offset + 356, 16672354);
            Write32(image, offset + 360, -16847162);
            Write32(image, offset + 364, 13027030);
            Write32(image, offset + 368, -554244410);
            Write32(image, offset + 372, 13027022);
            Write32(image, offset + 376, -960051588);
            Write32(image, offset + 380, 8177350);
            Write32(image, offset + 384, 2087085820);
            Write32(image, offset + 388, 15753312);
            Write32(image, offset + 392, -960051588);
            Write32(image, offset + 396, 243060422);
            Write32(image, offset + 400, 2087085820);
            Write32(image, offset + 404, 15099500);
            Write32(image, offset + 408, 405825084);
            Write32(image, offset + 412, 3958284);
            Write32(image, offset + 416, 408583806);
            Write32(image, offset + 420, 3938328);
            Write32(image, offset + 424, -960051514);
            Write32(image, offset + 428, 8177350);
            Write32(image, offset + 432, -960051514);
            Write32(image, offset + 436, 3697862);
            Write32(image, offset + 440, -691616058);
            Write32(image, offset + 444, 7143126);
            Write32(image, offset + 448, 946652870);
            Write32(image, offset + 452, 13026924);
            Write32(image, offset + 456, 1013343846);
            Write32(image, offset + 460, 3938328);
            Write32(image, offset + 464, 411879166);
            Write32(image, offset + 468, 16672306);
            Write32(image, offset + 472, 808464444);
            Write32(image, offset + 476, 3944496);
            Write32(image, offset + 480, 405823680);
            Write32(image, offset + 484, 132620);
            Write32(image, offset + 488, 202116156);
            Write32(image, offset + 492, 3935244);
            Write32(image, offset + 496, -965986288);
            Write32(image, offset + 500, 0);
            Write32(image, offset + 504, 0);
            Write32(image, offset + 508, -16777216);
            Write32(image, offset + 512, 792624);
            Write32(image, offset + 516, 0);
            Write32(image, offset + 520, 209190912);
            Write32(image, offset + 524, 7785596);
            Write32(image, offset + 528, 1719427296);
            Write32(image, offset + 532, 14444134);
            Write32(image, offset + 536, -964952064);
            Write32(image, offset + 540, 8177344);
            Write32(image, offset + 544, -864285668);
            Write32(image, offset + 548, 7785676);
            Write32(image, offset + 552, -964952064);
            Write32(image, offset + 556, 8175870);
            Write32(image, offset + 560, -127900100);
            Write32(image, offset + 564, 15753312);
            Write32(image, offset + 568, -864681984);
            Write32(image, offset + 572, -133399348);
            Write32(image, offset + 576, 1986814176);
            Write32(image, offset + 580, 15099494);
            Write32(image, offset + 584, 406323224);
            Write32(image, offset + 588, 3938328);
            Write32(image, offset + 592, 101056518);
            Write32(image, offset + 596, 1013343750);
            Write32(image, offset + 600, 1818648800);
            Write32(image, offset + 604, 15101048);
            Write32(image, offset + 608, 404232248);
            Write32(image, offset + 612, 3938328);
            Write32(image, offset + 616, -18087936);
            Write32(image, offset + 620, 14079702);
            Write32(image, offset + 624, 1725693952);
            Write32(image, offset + 628, 6710886);
            Write32(image, offset + 632, -964952064);
            Write32(image, offset + 636, 8177350);
            Write32(image, offset + 640, 1725693952);
            Write32(image, offset + 644, -262112154);
            Write32(image, offset + 648, -864681984);
            Write32(image, offset + 652, 504134860);
            Write32(image, offset + 656, 1994129408);
            Write32(image, offset + 660, 15753312);
            Write32(image, offset + 664, -1065484288);
            Write32(image, offset + 668, 16516732);
            Write32(image, offset + 672, 821833776);
            Write32(image, offset + 676, 1848880);
            Write32(image, offset + 680, -859045888);
            Write32(image, offset + 684, 7785676);
            Write32(image, offset + 688, -960102400);
            Write32(image, offset + 692, 3697862);
            Write32(image, offset + 696, -691666944);
            Write32(image, offset + 700, 7143126);
            Write32(image, offset + 704, 1824915456);
            Write32(image, offset + 708, 13003832);
            Write32(image, offset + 712, -960102400);
            Write32(image, offset + 716, -66683194);
            Write32(image, offset + 720, 1283325952);
            Write32(image, offset + 724, 8270360);
            Write32(image, offset + 728, 1880627214);
            Write32(image, offset + 732, 923672);
            Write32(image, offset + 736, 404232216);
            Write32(image, offset + 740, 1579032);
            Write32(image, offset + 744, 236460144);
            Write32(image, offset + 748, 7346200);
            Write32(image, offset + 752, 56438);
            Write32(image, offset + 756, 0);
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
