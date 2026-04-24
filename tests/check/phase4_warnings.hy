public class Program {
    private int unusedField;

    private static void UnusedPrivate() {
        System.Console.WriteLine("unused");
    }

    public static void Main(string[] args) {
        unsafe {
        }
        unsafe {
            int value = 1;
            System.Console.WriteLine(value);
        }
        if (args.Length >= 0) {
            return;
            System.Console.WriteLine("nested unreachable");
        }
    }
}
