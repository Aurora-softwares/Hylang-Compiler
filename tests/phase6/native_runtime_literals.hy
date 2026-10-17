public class Program {
    public static int Main() {
        int before = System.Runtime.GC.GetAllocatedBytes();
        int matches = 0;
        int i = 0;
        while (i < 50) {
            if ("E" == "E") { matches = matches + 1; }
            i = i + 1;
        }
        int after = System.Runtime.GC.GetAllocatedBytes();
        if (matches != 50 || after - before > 65536) { return 91; }
        string text = "hello";
        System.Runtime.GC.Collect();
        if (text.Length != 5 || text[0] != "h" || text[4] != "o") { return 92; }
        System.Console.WriteLine("literal allocation ok");
        return 42;
    }
}
