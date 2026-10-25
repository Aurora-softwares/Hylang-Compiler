public class Program {
    public static int Main(string[] args) {
        if (args.Length == 0) {
            if (System.Host.Process.IsWindows()) { return 2; }
            return 3;
        }
        return System.Host.Process.Run(args[0]);
    }
}
