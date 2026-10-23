public class Box { public int value; }

public class Program {
    private static int calls;
    private static int Index() { calls = calls + 1; return 0; }
    private static Box GetBox(Box box) { calls = calls + 1; return box; }

    public static int Main(string[] args) {
        int value = 5;
        value += 3; value -= 2; value *= 4; value /= 3;
        value %= 5; value &= 2; value |= 4; value ^= 1;
        if (value != 7) { return 11; }
        int result = (value += 1);
        if (result != 8 || value != 8) { return 12; }

        int[] numbers = new int[1];
        numbers[0] = 10;
        calls = 0;
        numbers[Index()] += 5;
        if (calls != 1 || numbers[0] != 15) { return 13; }

        Box box = new Box(); box.value = 10;
        calls = 0;
        GetBox(box).value *= 2;
        if (calls != 1 || box.value != 20) { return 14; }

        byte small = (byte)250; small += 10;
        if (small != (byte)4) { return 15; }
        int shifted = 3;
        shifted <<= 2; shifted >>= 1;
        if (shifted != 6) { return 16; }
        byte narrow = (byte)1; narrow <<= 8;
        if (narrow != (byte)1) { return 17; }
        int negative = -8; negative >>= 1;
        if (negative != -4) { return 18; }
        int reordered = 1;
        reordered += (reordered = 2);
        if (reordered != 3) { return 19; }
        int nested = 1;
        nested += (nested += 2);
        if (nested != 4) { return 20; }
        return 42;
    }
}
