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
        return 42;
    }
}
