public class Program {
    public static int Main(string[] args) {
        if (args.Length != 2 || args[1] != "two words") { return 91; }
        string path = args[0];
        System.IO.File.WriteAllText(path, "Windows runtime\n");
        if (!System.IO.File.Exists(path)) { return 92; }
        string content = System.IO.File.ReadAllText(path);
        if (content != "Windows runtime\n") { return 93; }
        byte[] bytes = System.IO.File.ReadAllBytes(path);
        if (bytes.Length != 16 || bytes[0] != (byte)87) { return 94; }
        byte[] output = new byte[3];
        output[0] = (byte)0;
        output[1] = (byte)255;
        output[2] = (byte)42;
        System.IO.File.WriteAllBytes(path, output);
        byte[] loaded = System.IO.File.ReadAllBytes(path);
        if (loaded.Length != 3 || loaded[0] != (byte)0 ||
            loaded[1] != (byte)255 || loaded[2] != (byte)42) { return 95; }
        int i = 0;
        string retained = "retained";
        while (i < 600) { string temporary = "discard" + i; i = i + 1; }
        System.Runtime.GC.Collect();
        if (retained != "retained") { return 96; }
        System.Console.WriteLine("windows runtime parity ok");
        return 42;
    }
}
