public class Program {
    public static int Main(string[] args) {
        // These path constants are stored in read-only ELF memory. The
        // Linux native runtime must not overwrite their slash characters.
        System.IO.File.WriteAllText("build/native-literal-path-test/nested/text.txt", "literal path is safe");
        string text = System.IO.File.ReadAllText("build/native-literal-path-test/nested/text.txt");
        if (text != "literal path is safe") { return 1; }
        byte[] value = new byte[2];
        value[0] = (byte)65;
        value[1] = (byte)90;
        System.IO.File.WriteAllBytes("build/native-literal-path-test/nested/data.bin", value);
        byte[] copy = System.IO.File.ReadAllBytes("build/native-literal-path-test/nested/data.bin");
        if (copy.Length != 2 || copy[0] != (byte)65 || copy[1] != (byte)90) { return 2; }
        System.Console.WriteLine("immutable native file paths passed");
        return 0;
    }
}
