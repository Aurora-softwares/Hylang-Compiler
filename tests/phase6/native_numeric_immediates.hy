public class Program {
    public static int Check(int value) {
        int three = 3;
        int seventeen = 17;
        int negative = -11;
        if (value + 3 != value + three) { return 1; }
        if (value - 3 != value - three) { return 2; }
        if (value * 17 != value * seventeen) { return 3; }
        if ((value < 3) != (value < three)) { return 4; }
        if ((value <= 3) != (value <= three)) { return 5; }
        if ((value > 3) != (value > three)) { return 6; }
        if ((value >= 3) != (value >= three)) { return 7; }
        if ((value == 3) != (value == three)) { return 8; }
        if ((value != 3) != (value != three)) { return 9; }
        if (value + -11 != value + negative) { return 10; }
        return 0;
    }

    public static int Main() {
        if (Check(-2147483647 - 1) != 0 || Check(-1000003) != 0 ||
            Check(-1) != 0 || Check(0) != 0 || Check(3) != 0 ||
            Check(1000003) != 0 || Check(2147483647) != 0) { return 90; }
        uint unsignedValue = (uint)-1;
        uint one = (uint)1;
        if ((unsignedValue > 1) != (unsignedValue > one)) { return 91; }
        if ((unsignedValue < 1) != (unsignedValue < one)) { return 92; }
        System.Console.WriteLine("numeric immediates ok");
        return 42;
    }
}
