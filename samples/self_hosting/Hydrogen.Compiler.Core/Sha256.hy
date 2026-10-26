namespace Hydrogen.Compiler.Core {
    // FIPS 180-4 SHA-256. Package hashes use the exact archive bytes.
    public class Sha256 {
        public static string Hex(byte[] input) {
            string constants =
                "428a2f9871374491b5c0fbcfe9b5dba53956c25b59f111f1923f82a4ab1c5ed5" +
                "d807aa9812835b01243185be550c7dc372be5d7480deb1fe9bdc06a7c19bf174" +
                "e49b69c1efbe47860fc19dc6240ca1cc2de92c6f4a7484aa5cb0a9dc76f988da" +
                "983e5152a831c66db00327c8bf597fc7c6e00bf3d5a7914706ca635114292967" +
                "27b70a852e1b21384d2c6dfc53380d13650a7354766a0abb81c2c92e92722c85" +
                "a2bfe8a1a81a664bc24b8b70c76c51a3d192e819d6990624f40e3585106aa070" +
                "19a4c1161e376c082748774c34b0bcb5391c0cb34ed8aa4a5b9cca4f682e6ff3" +
                "748f82ee78a5636f84c878148cc7020890befffaa4506cebbef9a3f7c67178f2";
            uint[] rounds = new uint[64];
            int cursor = 0;
            int round = 0;
            while (round < 64) {
                uint value = (uint)0;
                int digit = 0;
                while (digit < 8) {
                    value = (value << 4) | (uint)Digit(constants[cursor]);
                    cursor = cursor + 1;
                    digit = digit + 1;
                }
                rounds[round] = value;
                round = round + 1;
            }

            uint[] state = new uint[8];
            state[0] = (uint)0x6a09e667; state[1] = (uint)0xbb67ae85;
            state[2] = (uint)0x3c6ef372; state[3] = (uint)0xa54ff53a;
            state[4] = (uint)0x510e527f; state[5] = (uint)0x9b05688c;
            state[6] = (uint)0x1f83d9ab; state[7] = (uint)0x5be0cd19;

            int paddedLength = ((input.Length + 9 + 63) / 64) * 64;
            byte[] padded = new byte[paddedLength];
            int i = 0;
            while (i < input.Length) { padded[i] = input[i]; i = i + 1; }
            padded[input.Length] = (byte)128;
            ulong bitLength = (ulong)input.Length * (ulong)8;
            i = 0;
            while (i < 8) {
                padded[paddedLength - 1 - i] = (byte)(bitLength & (ulong)255);
                bitLength = bitLength >> 8;
                i = i + 1;
            }

            int block = 0;
            while (block < paddedLength) {
                uint[] words = new uint[64];
                i = 0;
                while (i < 16) {
                    int offset = block + i * 4;
                    words[i] = ((uint)padded[offset] << 24) |
                        ((uint)padded[offset + 1] << 16) |
                        ((uint)padded[offset + 2] << 8) | (uint)padded[offset + 3];
                    i = i + 1;
                }
                while (i < 64) {
                    uint x = words[i - 15];
                    uint y = words[i - 2];
                    uint sigma0 = Rotate(x, 7) ^ Rotate(x, 18) ^ (x >> 3);
                    uint sigma1 = Rotate(y, 17) ^ Rotate(y, 19) ^ (y >> 10);
                    words[i] = words[i - 16] + sigma0 + words[i - 7] + sigma1;
                    i = i + 1;
                }
                uint a = state[0]; uint b = state[1];
                uint c = state[2]; uint d = state[3];
                uint e = state[4]; uint f = state[5];
                uint g = state[6]; uint h = state[7];
                i = 0;
                while (i < 64) {
                    uint upper1 = Rotate(e, 6) ^ Rotate(e, 11) ^ Rotate(e, 25);
                    uint choice = (e & f) ^ (~e & g);
                    uint temp1 = h + upper1 + choice + rounds[i] + words[i];
                    uint upper0 = Rotate(a, 2) ^ Rotate(a, 13) ^ Rotate(a, 22);
                    uint majority = (a & b) ^ (a & c) ^ (b & c);
                    uint temp2 = upper0 + majority;
                    h = g; g = f; f = e; e = d + temp1;
                    d = c; c = b; b = a; a = temp1 + temp2;
                    i = i + 1;
                }
                state[0] = state[0] + a; state[1] = state[1] + b;
                state[2] = state[2] + c; state[3] = state[3] + d;
                state[4] = state[4] + e; state[5] = state[5] + f;
                state[6] = state[6] + g; state[7] = state[7] + h;
                block = block + 64;
            }

            string hex = "0123456789abcdef";
            string result = "";
            i = 0;
            while (i < 8) {
                int shift = 28;
                while (shift >= 0) {
                    result = result + hex[(int)((state[i] >> shift) & (uint)15)];
                    shift = shift - 4;
                }
                i = i + 1;
            }
            return result;
        }

        private static uint Rotate(uint value, int count) {
            return (value >> count) | (value << (32 - count));
        }

        private static int Digit(string ch) {
            string digits = "0123456789abcdef";
            int i = 0;
            while (i < 16) {
                if (digits[i] == ch) { return i; }
                i = i + 1;
            }
            return 0;
        }
    }
}
