public class Program {
    public static int Main(string[] args) {
        int a = 10;
        int b = 12;
        if ((a & b) != 8) { return 11; }
        if ((a | b) != 14) { return 12; }
        if ((a ^ b) != 6) { return 13; }
        if (~a != -11) { return 14; }
        if ((1 | 2 & 4) != 1) { return 15; }
        if ((1 ^ 3 & 2) != 3) { return 16; }
        byte small = (byte)5;
        byte other = (byte)3;
        if ((small & other) != (byte)1) { return 17; }
        if ((~small) != (byte)250) { return 18; }
        if ((1 << 3) != 8) { return 19; }
        if ((16 >> 2) != 4) { return 20; }
        if ((-8 >> 1) != -4) { return 21; }
        uint unsignedValue = (uint)(1 << 31);
        if ((unsignedValue >> 1) != (uint)0x40000000) { return 22; }
        if ((1 << 33) != 2) { return 23; }
        if (((1 + 1) << 2) != 8) { return 24; }
        if ((small << 1) != (byte)10) { return 25; }
        if (((byte)1 << 8) != (byte)1) { return 26; }
        long wide = (long)1 << 40;
        if ((wide >> 40) != (long)1) { return 27; }
        ulong highBit = (ulong)1 << 63;
        if ((highBit >> 63) != (ulong)1) { return 28; }
        sbyte negative = (sbyte)-8;
        if ((negative >> 1) != (sbyte)-4) { return 29; }
        if ((~negative) != (sbyte)7) { return 30; }
        return 42;
    }
}
