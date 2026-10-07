public class Counter {
    private static int value = 40;
    public static string Label = "static fields ok";

    public static int Next() {
        value = value + 1;
        return value;
    }
}

public class Program {
    public static int Main(string[] args) {
        int first = Counter.Next();
        int second = Counter.Next();
        System.Runtime.GC.Collect();
        System.Console.WriteLine(Counter.Label);
        if (first != 41) {
            return 1;
        }
        return second;
    }
}
