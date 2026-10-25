public class Program {
    public static int SignedMask(int left, int right) {
        int mask = 0;
        if (left < right) { mask = mask + 1; }
        if (left <= right) { mask = mask + 2; }
        if (left > right) { mask = mask + 4; }
        if (left >= right) { mask = mask + 8; }
        return mask;
    }

    public static int UnsignedMask(uint left, uint right) {
        int mask = 0;
        if (left < right) { mask = mask + 1; }
        if (left <= right) { mask = mask + 2; }
        if (left > right) { mask = mask + 4; }
        if (left >= right) { mask = mask + 8; }
        return mask;
    }

    public static int Main() {
        if (SignedMask(-2147483647 - 1, 1) != 3 || SignedMask(1, 1) != 10 ||
            SignedMask(2147483647, -1) != 12) { return 1; }
        uint maximum = (uint)-1;
        uint one = (uint)1;
        if (UnsignedMask(maximum, one) != 12 || UnsignedMask(one, maximum) != 3 ||
            UnsignedMask(one, one) != 10) { return 2; }
        int count = 0;
        int i = -2;
        int limit = 2;
        while (i < limit) { count = count + 1; i = i + 1; }
        for (int j = 0; j <= 3; j = j + 1) { count = count + 1; }
        byte[] values = new byte[3];
        i = 0;
        while (i < values.Length) { count = count + 1; i = i + 1; }
        if (count != 11) { return 3; }
        System.Console.WriteLine("condition branches ok");
        return 42;
    }
}
