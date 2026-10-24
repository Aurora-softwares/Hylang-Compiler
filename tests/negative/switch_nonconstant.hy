public class Program {
    private static int Value() { return 1; }
    public static int Main() {
        switch (1) {
            case Value(): break;
        }
        return 0;
    }
}
