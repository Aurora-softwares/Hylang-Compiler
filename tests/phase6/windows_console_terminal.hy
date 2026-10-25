public class Program {
    public static int Main(string[] args) {
        // The parity harness captures stdout, so the handle is a pipe.
        if (System.Console.IsTerminal()) { return 91; }
        System.Console.WriteLine("console pipe detected");
        return 42;
    }
}
