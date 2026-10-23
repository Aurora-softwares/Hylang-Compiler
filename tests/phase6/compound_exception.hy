public class Program {
    private static int Fail() { throw "boom"; }

    public static int Main() {
        int value = 1;
        try {
            value += Fail();
        } catch (string message) {
            if (message != "boom") { return 11; }
        }
        value += 2;
        if (value != 3) { return 12; }
        return 42;
    }
}
