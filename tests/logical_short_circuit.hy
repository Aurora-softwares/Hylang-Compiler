public class Program {
    public static bool FailIfCalled() {
        int[] values = new int[1];
        return values[1] == 0;
    }

    public static void Main() {
        if (false && FailIfCalled()) { System.Console.WriteLine("bad-and"); return; }
        if (true || FailIfCalled()) { System.Console.WriteLine("short-circuit-ok"); return; }
        System.Console.WriteLine("bad-or");
    }
}
