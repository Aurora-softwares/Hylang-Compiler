using System.IO;
using System.Runtime;

namespace HexLab.Core {
    public class HexText {
        public static string Nibble(int value) {
            if (value == 0) { return "0"; }
            if (value == 1) { return "1"; }
            if (value == 2) { return "2"; }
            if (value == 3) { return "3"; }
            if (value == 4) { return "4"; }
            if (value == 5) { return "5"; }
            if (value == 6) { return "6"; }
            if (value == 7) { return "7"; }
            if (value == 8) { return "8"; }
            if (value == 9) { return "9"; }
            if (value == 10) { return "A"; }
            if (value == 11) { return "B"; }
            if (value == 12) { return "C"; }
            if (value == 13) { return "D"; }
            if (value == 14) { return "E"; }
            return "F";
        }

        public static string ByteHex(int value) {
            int high = value / 16;
            int low = value % 16;
            return Nibble(high) + Nibble(low);
        }

        public static int HexValue(string digit) {
            if (digit == "0") { return 0; }
            if (digit == "1") { return 1; }
            if (digit == "2") { return 2; }
            if (digit == "3") { return 3; }
            if (digit == "4") { return 4; }
            if (digit == "5") { return 5; }
            if (digit == "6") { return 6; }
            if (digit == "7") { return 7; }
            if (digit == "8") { return 8; }
            if (digit == "9") { return 9; }
            if (digit == "A" || digit == "a") { return 10; }
            if (digit == "B" || digit == "b") { return 11; }
            if (digit == "C" || digit == "c") { return 12; }
            if (digit == "D" || digit == "d") { return 13; }
            if (digit == "E" || digit == "e") { return 14; }
            if (digit == "F" || digit == "f") { return 15; }
            return -1;
        }

        public static string CompactHex(string text) {
            string result = "";
            int index = 0;
            while (index < text.Length) {
                string ch = text[index];
                if (ch != " " && ch != "-" && ch != "_") {
                    result = result + ch;
                }
                index = index + 1;
            }
            return result;
        }

        public static byte[] ParseHexPattern(string text) {
            string compact = CompactHex(text);
            if (compact.Length == 0 || compact.Length % 2 != 0) {
                return new byte[0];
            }

            byte[] result = new byte[compact.Length / 2];
            int sourceIndex = 0;
            int resultIndex = 0;
            while (sourceIndex < compact.Length) {
                int high = HexValue(compact[sourceIndex]);
                int low = HexValue(compact[sourceIndex + 1]);
                if (high < 0 || low < 0) {
                    return new byte[0];
                }
                result[resultIndex] = high * 16 + low;
                sourceIndex = sourceIndex + 2;
                resultIndex = resultIndex + 1;
            }
            return result;
        }
    }

    public class HexLab {
        public static int Min(int left, int right) {
            if (left < right) {
                return left;
            }
            return right;
        }

        public static byte[] ReadAllBytes(string path) {
            return File.ReadAllBytes(path);
        }

        public static Buffer ReadBuffer(string path) {
            return Buffer.FromArray(ReadAllBytes(path));
        }

        public static string Dump(byte[] data, int width, int start, int count) {
            Buffer buffer = Buffer.FromArray(data);
            if (width <= 0) {
                width = 16;
            }
            if (start < 0) {
                start = 0;
            }
            if (count < 0 || start + count > buffer.Length()) {
                count = buffer.Length() - start;
            }

            string result = "";
            int index = start;
            int end = start + count;
            while (index < end) {
                int lineCount = Min(width, end - index);
                result = result + index + ": ";
                int inner = 0;
                while (inner < lineCount) {
                    if (inner > 0) {
                        result = result + " ";
                    }
                    result = result + HexText.ByteHex(buffer.Get(index + inner));
                    inner = inner + 1;
                }
                index = index + lineCount;
                if (index < end) {
                    result = result + "\n";
                }
            }
            return result;
        }

        public static string DumpFile(string path, int width, int start, int count) {
            return Dump(ReadAllBytes(path), width, start, count);
        }

        public static string Inspect(byte[] data) {
            if (data.Length >= 24 &&
                BinaryPrimitives.ReadInt64BE(data, 0) == -8552249625308161526) {
                int width = BinaryPrimitives.ReadUInt32BE(data, 16);
                int height = BinaryPrimitives.ReadUInt32BE(data, 20);
                return "format=PNG width=" + width + " height=" + height;
            }

            if (data.Length >= 30 &&
                data[0] == 80 &&
                data[1] == 75 &&
                data[2] == 3 &&
                data[3] == 4) {
                int method = BinaryPrimitives.ReadUInt16LE(data, 8);
                int nameLength = BinaryPrimitives.ReadUInt16LE(data, 26);
                int extraLength = BinaryPrimitives.ReadUInt16LE(data, 28);
                return "format=ZIP method=" + method + " name_length=" + nameLength + " extra_length=" + extraLength;
            }

            if (data.Length >= 20 &&
                data[0] == 127 &&
                data[1] == 69 &&
                data[2] == 76 &&
                data[3] == 70) {
                return "format=ELF class=" + data[4] + " endian=" + data[5];
            }

            if (data.Length >= 64 &&
                data[0] == 77 &&
                data[1] == 90) {
                int peOffset = BinaryPrimitives.ReadUInt32LE(data, 60);
                if (peOffset + 4 <= data.Length &&
                    data[peOffset] == 80 &&
                    data[peOffset + 1] == 69 &&
                    data[peOffset + 2] == 0 &&
                    data[peOffset + 3] == 0) {
                    return "format=PE pe_offset=" + peOffset;
                }
                return "format=MZ";
            }

            return "format=Unknown";
        }

        public static string InspectFile(string path) {
            return Inspect(ReadAllBytes(path));
        }

        public static string Diff(byte[] left, byte[] right) {
            Buffer leftBuffer = Buffer.FromArray(left);
            Buffer rightBuffer = Buffer.FromArray(right);
            int limit = Min(leftBuffer.Length(), rightBuffer.Length());
            int index = 0;
            while (index < limit) {
                int leftByte = leftBuffer.Get(index);
                int rightByte = rightBuffer.Get(index);
                if (leftByte != rightByte) {
                    return "diff offset=" + index + " left=" + HexText.ByteHex(leftByte) + " right=" + HexText.ByteHex(rightByte);
                }
                index = index + 1;
            }
            if (leftBuffer.Length() != rightBuffer.Length()) {
                return "diff length left=" + leftBuffer.Length() + " right=" + rightBuffer.Length();
            }
            return "equal";
        }

        public static string DiffFiles(string leftPath, string rightPath) {
            return Diff(ReadAllBytes(leftPath), ReadAllBytes(rightPath));
        }

        public static int FindPattern(byte[] data, byte[] pattern) {
            Buffer buffer = Buffer.FromArray(data);
            if (pattern.Length == 0 || pattern.Length > buffer.Length()) {
                return -1;
            }

            int index = 0;
            while (index <= buffer.Length() - pattern.Length) {
                int matchIndex = 0;
                bool matches = true;
                while (matchIndex < pattern.Length) {
                    if (buffer.Get(index + matchIndex) != pattern[matchIndex]) {
                        matches = false;
                        break;
                    }
                    matchIndex = matchIndex + 1;
                }
                if (matches) {
                    return index;
                }
                index = index + 1;
            }
            return -1;
        }

        public static int FindPatternUnsafe(byte[] data, byte[] pattern) {
            Buffer dataBuffer = Buffer.FromArray(data);
            Buffer patternBuffer = Buffer.FromArray(pattern);
            if (patternBuffer.Length() == 0 || patternBuffer.Length() > dataBuffer.Length()) {
                return -1;
            }

            int found = -1;
            unsafe {
                byte* dataStart = dataBuffer.DangerousData();
                byte* patternStart = patternBuffer.DangerousData();
                int index = 0;
                int limit = dataBuffer.Length() - patternBuffer.Length();
                while (index <= limit) {
                    byte* cursor = dataStart + index;
                    int matchIndex = 0;
                    bool matches = true;
                    while (matchIndex < patternBuffer.Length()) {
                        if (cursor[matchIndex] != patternStart[matchIndex]) {
                            matches = false;
                            break;
                        }
                        matchIndex = matchIndex + 1;
                    }
                    if (matches) {
                        found = cursor - dataStart;
                        break;
                    }
                    index = index + 1;
                }
                Memory.Free(dataStart);
                Memory.Free(patternStart);
            }
            return found;
        }

        public static string Search(byte[] data, string hexPattern) {
            byte[] pattern = HexText.ParseHexPattern(hexPattern);
            int found = FindPatternUnsafe(data, pattern);
            if (found < 0) {
                return "not found";
            }
            return "found offset=" + found;
        }

        public static string SearchFile(string path, string hexPattern) {
            return Search(ReadAllBytes(path), hexPattern);
        }

        public static byte[] Slice(byte[] data, int start, int count) {
            Buffer buffer = Buffer.FromArray(data);
            if (start < 0) {
                start = 0;
            }
            if (count < 0 || start + count > buffer.Length()) {
                count = buffer.Length() - start;
            }
            return buffer.Slice(start, count).ToArray();
        }

        public static string SliceFile(string path, int start, int count, string outPath) {
            byte[] slice = Slice(ReadAllBytes(path), start, count);
            File.WriteAllBytes(outPath, slice);
            return "wrote=" + slice.Length;
        }
    }
}
