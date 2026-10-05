public class Program {
    public static int Main(string[] args) {
        string seed = "12345678";
        int i = 0;
        while (i < 13) { seed = seed + seed; i = i + 1; }
        if (seed.Length != 65536) { return 90; }
        if (args[0] == "files") { System.IO.File.WriteAllText(args[1], seed); }
        i = 0;
        while (i < 4000) {
            if (args[0] == "arrays") {
                byte[] buffer = new byte[65536];
                buffer[65535] = (byte)42;
                if (buffer[65535] != (byte)42) { return 91; }
            } else if (args[0] == "strings") {
                string text = seed + "x";
                if (text.Length != 65537 || text[65536] != "x") { return 92; }
            } else {
                string text = System.IO.File.ReadAllText(args[1]);
                if (text != seed) { return 93; }
            }
            i = i + 1;
        }
        System.Console.WriteLine("managed payload accounting ok");
        return 0;
    }
}
