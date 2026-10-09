namespace Hydrogen.Compiler.CodeGen.X64 {
    // Small x86-64 runtime for the post-ExitBootServices method graph. R15 is
    // the KernelBootInfo pointer. Allocation consumes contiguous pages from
    // its primary physical range and never calls firmware or Linux.
    public class FreestandingRuntimeEmitter {
        private int allocOffset;
        private int arrayOffset;
        private int indexOffset;
        private int checkOffset;
        private int stringOffset;
        private int equalOffset;
        private int charOffset;
        private int byteAtOffset;
        private int fromBytesOffset;
        private int errorOffset;

        private int JumpIf(X64Assembler code, int condition) {
            code.EmitByte(0x0f); code.EmitByte(condition);
            int patch = code.Position(); code.Emit32(0); return patch;
        }

        private void Patch(X64Assembler code, int site, int target) {
            code.Patch32(site, target - (site + 4));
        }

        public void Emit(X64Assembler code) {
            int start = code.Position();
            allocOffset = code.Position() - start;
            code.EmitByte(0x53); code.EmitByte(0x51); code.EmitByte(0x52);
            code.EmitByte(0x57); code.EmitByte(0x56); // save rbx, rcx, rdx, rdi, rsi
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xf8); // rax = bytes
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xc0);
            int negativeSize = JumpIf(code, 0x88); // js
            int nonzeroSize = JumpIf(code, 0x85); // jnz
            code.EmitByte(0xb8); code.Emit32(16);
            Patch(code, nonzeroSize, code.Position());
            code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xc0); code.EmitByte(15);
            int alignOverflow = JumpIf(code, 0x82); // jc
            code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xe0); code.EmitByte(240); // 16-byte align
            code.EmitByte(0x48); code.EmitByte(0x05); code.Emit32(4095);
            int pageOverflow = JumpIf(code, 0x82);
            code.EmitByte(0x48); code.EmitByte(0x25); code.Emit32(-4096); // round to pages
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xc6); // rsi = reserved bytes
            code.EmitByte(0x49); code.EmitByte(0x8b); code.EmitByte(0x5f); code.EmitByte(40); // rbx = next
            code.EmitByte(0x48); code.EmitByte(0xf7); code.EmitByte(0xc3); code.Emit32(4095);
            int unaligned = JumpIf(code, 0x85);
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xda); // rdx = next
            code.EmitByte(0x48); code.EmitByte(0x01); code.EmitByte(0xf2); // rdx += bytes
            int rangeOverflow = JumpIf(code, 0x82);
            code.EmitByte(0x49); code.EmitByte(0x3b); code.EmitByte(0x57); code.EmitByte(48);
            int exhausted = JumpIf(code, 0x87); // ja limit
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0x57); code.EmitByte(40);
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0x5f); code.EmitByte(72);
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xdf); // rdi = start
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xf1); // rcx = bytes
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe9); code.EmitByte(3);
            code.EmitByte(0x31); code.EmitByte(0xc0); code.EmitByte(0xfc);
            code.EmitByte(0xf3); code.EmitByte(0x48); code.EmitByte(0xab); // zero pages
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xd8); // return start
            code.EmitByte(0x5e); code.EmitByte(0x5f); code.EmitByte(0x5a);
            code.EmitByte(0x59); code.EmitByte(0x5b); code.EmitByte(0xc3);

            arrayOffset = code.Position() - start;
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xff);
            int negativeArray = JumpIf(code, 0x88);
            code.EmitByte(0x48); code.EmitByte(0x81); code.EmitByte(0xff); code.Emit32(1048576);
            int largeArray = JumpIf(code, 0x87);
            code.EmitByte(0x57); // save element count
            code.EmitByte(0x48); code.EmitByte(0xc1); code.EmitByte(0xe7); code.EmitByte(3);
            code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xc7); code.EmitByte(8);
            code.EmitByte(0xe8); int allocCall = code.Position(); code.Emit32(0);
            code.EmitByte(0x59); // rcx = element count
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0x08); // [rax] = length
            code.EmitByte(0xc3);
            Patch(code, allocCall, start + allocOffset);

            indexOffset = code.Position() - start;
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xff);
            int nullArray = JumpIf(code, 0x84);
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xf6);
            int negativeIndex = JumpIf(code, 0x88);
            code.EmitByte(0x48); code.EmitByte(0x3b); code.EmitByte(0x37); // cmp index, length
            int outOfRange = JumpIf(code, 0x83); // jae
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x44);
            code.EmitByte(0xf7); code.EmitByte(8); code.EmitByte(0xc3);

            checkOffset = code.Position() - start;
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xff);
            int nullObject = JumpIf(code, 0x84);
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xf8); code.EmitByte(0xc3);

            // Copy an ASCII literal into a managed length-prefixed string.
            // rdi points to literal bytes and rsi is its length.
            stringOffset = code.Position() - start;
            code.EmitByte(0x53); code.EmitByte(0x41); code.EmitByte(0x54);
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xfb); // rbx = source
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xf4); // r12 = length
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x7e); code.EmitByte(9);
            code.EmitByte(0xe8); int stringAlloc = code.Position(); code.Emit32(0);
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0x20); // [rax] = length
            code.EmitByte(0x50); // preserve result during copy
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x78); code.EmitByte(8);
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xde); // rsi = source
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xe1); // rcx = length
            code.EmitByte(0xfc); code.EmitByte(0xf3); code.EmitByte(0xa4); // cld; rep movsb
            code.EmitByte(0xc6); code.EmitByte(0x07); code.EmitByte(0); // nul terminator
            code.EmitByte(0x58); code.EmitByte(0x41); code.EmitByte(0x5c);
            code.EmitByte(0x5b); code.EmitByte(0xc3);
            Patch(code, stringAlloc, start + allocOffset);

            // Managed string equality: pointer identity, nulls, length, then
            // exact bytes. This has the same calling convention as rt_equal in
            // the hosted runtime and never touches firmware services.
            equalOffset = code.Position() - start;
            code.EmitByte(0x48); code.EmitByte(0x39); code.EmitByte(0xf7); // cmp rdi, rsi
            int sameString = JumpIf(code, 0x84);
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xff);
            int nullLeft = JumpIf(code, 0x84);
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xf6);
            int nullRight = JumpIf(code, 0x84);
            code.EmitByte(0x48); code.EmitByte(0x8b); code.EmitByte(0x0f); // rcx = left length
            code.EmitByte(0x48); code.EmitByte(0x3b); code.EmitByte(0x0e); // cmp rcx, [rsi]
            int differentLength = JumpIf(code, 0x85);
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xc9);
            int emptyString = JumpIf(code, 0x84);
            code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xc7); code.EmitByte(8);
            code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xc6); code.EmitByte(8);
            code.EmitByte(0xfc); code.EmitByte(0xf3); code.EmitByte(0xa6); // cld; repe cmpsb
            int differentBytes = JumpIf(code, 0x85);
            int equalTrue = code.Position();
            code.EmitByte(0xb8); code.Emit32(1); code.EmitByte(0xc3);
            int equalFalse = code.Position();
            code.EmitByte(0x31); code.EmitByte(0xc0); code.EmitByte(0xc3);
            Patch(code, sameString, equalTrue);
            Patch(code, emptyString, equalTrue);
            Patch(code, nullLeft, equalFalse);
            Patch(code, nullRight, equalFalse);
            Patch(code, differentLength, equalFalse);
            Patch(code, differentBytes, equalFalse);

            // String indexing returns a managed one-character string.
            charOffset = code.Position() - start;
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xff);
            int nullString = JumpIf(code, 0x84);
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xf6);
            int negativeCharIndex = JumpIf(code, 0x88);
            code.EmitByte(0x48); code.EmitByte(0x3b); code.EmitByte(0x37);
            int charOutOfRange = JumpIf(code, 0x83);
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x7c);
            code.EmitByte(0x37); code.EmitByte(8); // rdi = string data + index
            code.EmitByte(0xbe); code.Emit32(1); // one byte
            code.EmitByte(0xe8); int charStringCall = code.Position(); code.Emit32(0);
            code.EmitByte(0xc3);
            Patch(code, charStringCall, start + stringOffset);

            // Read an unsigned byte from a managed string without allocating
            // a one-character managed string for serial output.
            byteAtOffset = code.Position() - start;
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xff);
            int nullByteString = JumpIf(code, 0x84);
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xf6);
            int negativeByteIndex = JumpIf(code, 0x88);
            code.EmitByte(0x48); code.EmitByte(0x3b); code.EmitByte(0x37);
            int byteOutOfRange = JumpIf(code, 0x83);
            code.EmitByte(0x0f); code.EmitByte(0xb6); code.EmitByte(0x44);
            code.EmitByte(0x37); code.EmitByte(8); code.EmitByte(0xc3);

            // Convert the first RSI byte-array elements into a managed ASCII
            // string. Array elements are 8-byte slots; only their low byte is
            // copied. RDI is the managed array pointer.
            fromBytesOffset = code.Position() - start;
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xff);
            int nullByteArray = JumpIf(code, 0x84);
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xf6);
            int negativeByteCount = JumpIf(code, 0x88);
            code.EmitByte(0x48); code.EmitByte(0x3b); code.EmitByte(0x37);
            int byteCountTooLarge = JumpIf(code, 0x87);
            code.EmitByte(0x53); code.EmitByte(0x41); code.EmitByte(0x54); code.EmitByte(0x41); code.EmitByte(0x55);
            code.EmitByte(0x48); code.EmitByte(0x89); code.EmitByte(0xfb); // rbx = array
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xf4); // r12 = count
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xe7); // rdi = count
            code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xc7); code.EmitByte(9);
            int byteStringOverflow = JumpIf(code, 0x82);
            code.EmitByte(0xe8); int fromBytesAlloc = code.Position(); code.Emit32(0);
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0x20); // [rax] = count
            code.EmitByte(0x49); code.EmitByte(0x89); code.EmitByte(0xc5); // r13 = result
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x78); code.EmitByte(8);
            code.EmitByte(0x48); code.EmitByte(0x8d); code.EmitByte(0x73); code.EmitByte(8);
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xe1); // rcx = count
            int byteCopy = code.Position();
            code.EmitByte(0x48); code.EmitByte(0x85); code.EmitByte(0xc9);
            int byteCopyDone = JumpIf(code, 0x84);
            code.EmitByte(0x8a); code.EmitByte(0x16); // dl = low byte of slot
            code.EmitByte(0x88); code.EmitByte(0x17); // [rdi] = dl
            code.EmitByte(0x48); code.EmitByte(0x83); code.EmitByte(0xc6); code.EmitByte(8);
            code.EmitByte(0x48); code.EmitByte(0xff); code.EmitByte(0xc7);
            code.EmitByte(0x48); code.EmitByte(0xff); code.EmitByte(0xc9);
            code.EmitByte(0xe9); int byteCopyBack = code.Position(); code.Emit32(0);
            Patch(code, byteCopyBack, byteCopy);
            Patch(code, byteCopyDone, code.Position());
            code.EmitByte(0xc6); code.EmitByte(0x07); code.EmitByte(0);
            code.EmitByte(0x4c); code.EmitByte(0x89); code.EmitByte(0xe8);
            code.EmitByte(0x41); code.EmitByte(0x5d); code.EmitByte(0x41); code.EmitByte(0x5c);
            code.EmitByte(0x5b); code.EmitByte(0xc3);
            Patch(code, fromBytesAlloc, start + allocOffset);

            errorOffset = code.Position() - start;
            // R15 is the KernelBootInfo pointer for freestanding code. Record
            // that a checked runtime precondition or allocation failed before
            // trapping, so post-handoff diagnostics distinguish it from an
            // unrelated invalid instruction.
            code.EmitByte(0x41); code.EmitByte(0xc7); code.EmitByte(0x87);
            code.Emit32(1160); code.Emit32(5);
            code.EmitByte(0x0f); code.EmitByte(0x0b); // ud2: fatal kernel exception
            Patch(code, negativeSize, start + errorOffset);
            Patch(code, alignOverflow, start + errorOffset);
            Patch(code, pageOverflow, start + errorOffset);
            Patch(code, unaligned, start + errorOffset);
            Patch(code, rangeOverflow, start + errorOffset);
            Patch(code, exhausted, start + errorOffset);
            Patch(code, negativeArray, start + errorOffset);
            Patch(code, largeArray, start + errorOffset);
            Patch(code, nullArray, start + errorOffset);
            Patch(code, negativeIndex, start + errorOffset);
            Patch(code, outOfRange, start + errorOffset);
            Patch(code, nullObject, start + errorOffset);
            Patch(code, nullString, start + errorOffset);
            Patch(code, negativeCharIndex, start + errorOffset);
            Patch(code, charOutOfRange, start + errorOffset);
            Patch(code, nullByteString, start + errorOffset);
            Patch(code, negativeByteIndex, start + errorOffset);
            Patch(code, byteOutOfRange, start + errorOffset);
            Patch(code, nullByteArray, start + errorOffset);
            Patch(code, negativeByteCount, start + errorOffset);
            Patch(code, byteCountTooLarge, start + errorOffset);
            Patch(code, byteStringOverflow, start + errorOffset);
        }

        public int Offset(string name) {
            if (name == "rt_alloc") { return allocOffset; }
            if (name == "rt_array") { return arrayOffset; }
            if (name == "rt_index") { return indexOffset; }
            if (name == "rt_check") { return checkOffset; }
            if (name == "rt_string") { return stringOffset; }
            if (name == "rt_equal") { return equalOffset; }
            if (name == "rt_char") { return charOffset; }
            if (name == "rt_byte_at") { return byteAtOffset; }
            if (name == "rt_from_bytes") { return fromBytesOffset; }
            if (name == "rt_null_error" || name == "rt_index_error" || name == "rt_size_error" ||
                name == "rt_oom") { return errorOffset; }
            return -1;
        }
    }
}
