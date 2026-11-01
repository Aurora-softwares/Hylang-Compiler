public class Program {
    public static int CheckModularFill(int n) {
        int[] values = new int[n];
        int i = 0;
        while (i < n) {
            values[i] = (i * 1000000 + 3) % 1000003;
            i = i + 1;
        }
        int factor = 1000000;
        int bias = 3;
        int divisor = 1000003;
        i = 0;
        while (i < n) {
            if (values[i] != (i * factor + bias) % divisor) { return 1; }
            i = i + 1;
        }
        return 0;
    }

    public static int CheckLongModularFill() {
        int n = 100005;
        int[] values = new int[n];
        int i = 0;
        while (i < n) {
            values[i] = (i * 17 + 3) % 1000003;
            i = i + 1;
        }
        int factor = 17;
        int bias = 3;
        int divisor = 1000003;
        i = 0;
        while (i < n) {
            if (values[i] != (i * factor + bias) % divisor) { return 1; }
            i = i + 1;
        }
        return 0;
    }

    public static int CheckFolded(int value) {
        int factor = 17;
        int bias = 3;
        int subtract = 5;
        int expected = value * factor;
        expected = expected + bias;
        if (value * 17 + 3 != expected) { return 1; }
        expected = value - subtract;
        expected = expected * factor;
        if ((value - 5) * 17 != expected) { return 2; }
        expected = value + bias;
        expected = expected - subtract;
        if ((value + 3) - 5 != expected) { return 3; }
        return 0;
    }

    public static int Check(int value) {
        int divisor = 3;
        if (value / 3 != value / divisor || value % 3 != value % divisor) { return 1; }
        divisor = 4;
        if (value / 4 != value / divisor || value % 4 != value % divisor) { return 2; }
        divisor = 7;
        if (value / 7 != value / divisor || value % 7 != value % divisor) { return 7; }
        divisor = 13;
        if (value / 13 != value / divisor || value % 13 != value % divisor) { return 3; }
        divisor = 97;
        if (value / 97 != value / divisor || value % 97 != value % divisor) { return 4; }
        divisor = 1000003;
        if (value / 1000003 != value / divisor || value % 1000003 != value % divisor) { return 5; }
        divisor = 255;
        if (value / 255 != value / divisor || value % 255 != value % divisor) { return 8; }
        divisor = 256;
        if (value / 256 != value / divisor || value % 256 != value % divisor) { return 9; }
        divisor = 257;
        if (value / 257 != value / divisor || value % 257 != value % divisor) { return 10; }
        divisor = 2147483647;
        if (value / 2147483647 != value / divisor || value % 2147483647 != value % divisor) { return 6; }
        return 0;
    }

    public static int Main() {
        int minimum = -2147483647 - 1;
        if (Check(minimum) != 0 || Check(-1000004) != 0 || Check(-1) != 0 ||
            Check(0) != 0 || Check(1) != 0 || Check(1000004) != 0 ||
            Check(2147483647) != 0) { return 90; }
        if (CheckFolded(minimum) != 0 || CheckFolded(-1) != 0 ||
            CheckFolded(0) != 0 || CheckFolded(1) != 0 ||
            CheckFolded(2147483647) != 0) { return 93; }
        int state = 1;
        int i = 0;
        while (i < 10000) {
            state = (state * 17 + 11) % 1000003;
            if (Check(state) != 0 || Check(-state) != 0) { return 91; }
            i = i + 1;
        }
        int limit = 10000;
        int sum = 0;
        i = 0;
        while (i < limit) {
            sum = sum + i % 13 + i / 97;
            i = i + 1;
        }
        if (sum != 570453) { return 92; }
        if (CheckModularFill(2147) != 0 || CheckModularFill(2148) != 0 ||
            CheckLongModularFill() != 0) { return 94; }
        System.Console.WriteLine("constant division ok");
        return 42;
    }
}
