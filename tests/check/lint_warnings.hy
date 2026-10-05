using System.IO;

public class Program {
    public static void Main(string[] args) {
        int unusedLocal = 1;
        if (args.Length >= 0) {
            int args = 2;
            System.Console.WriteLine(args);
        }
        UnusedParameter(5);
        StopEarly();
    }

    public static void UnusedParameter(int value) {
        System.Console.WriteLine("lint");
    }

    public static void StopEarly() {
        return;
        System.Console.WriteLine("after");
    }
}
