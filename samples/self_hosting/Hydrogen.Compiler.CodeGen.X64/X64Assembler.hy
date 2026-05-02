namespace Hydrogen.Compiler.CodeGen.X64 {
    public class X64Assembler {
        private byte[] buffer;
        private int count;

        public X64Assembler() {
            buffer = new byte[256];
            count = 0;
        }

        public int Position() {
            return count;
        }

        public void EmitByte(int value) {
            Ensure(1);
            buffer[count] = (byte)value;
            count = count + 1;
        }

        public void Emit32(int value) {
            int temp = value;
            EmitByte(Mod256(temp));
            temp = temp / 256;
            EmitByte(Mod256(temp));
            temp = temp / 256;
            EmitByte(Mod256(temp));
            temp = temp / 256;
            EmitByte(Mod256(temp));
        }

        public void Emit64(long value) {
            long temp = value;
            int i = 0;
            while (i < 8) {
                EmitByte((int)(temp % 256));
                temp = temp / 256;
                i = i + 1;
            }
        }

        public byte[] ToArray() {
            byte[] result = new byte[count];
            int i = 0;
            while (i < count) {
                result[i] = buffer[i];
                i = i + 1;
            }
            return result;
        }

        private void Ensure(int extra) {
            if (count + extra <= buffer.Length) {
                return;
            }
            int newSize = buffer.Length * 2;
            while (newSize < count + extra) {
                newSize = newSize * 2;
            }
            byte[] next = new byte[newSize];
            int i = 0;
            while (i < buffer.Length) {
                next[i] = buffer[i];
                i = i + 1;
            }
            buffer = next;
        }

        private int Mod256(int value) {
            int result = value % 256;
            if (result < 0) {
                result = result + 256;
            }
            return result;
        }
    }
}
