public class Program {
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
        int state = 1;
        int i = 0;
        while (i < 10000) {
            state = (state * 17 + 11) % 1000003;
            if (Check(state) != 0 || Check(-state) != 0) { return 91; }
            i = i + 1;
        }
        System.Console.WriteLine("constant division ok");
        return 42;
    }
}
