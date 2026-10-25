public class Program {
    public static int Main(string[] args) {
        if (args.Length != 2) { return 2; }
        int n = System.Convert.ToInt32(args[1]);
        if (n < 0 || n > 100000) { return 2; }
        if (args[0] == "builder") {
            TextBuilder builder = new TextBuilder();
            int i = 0;
            while (i < n) { builder.Append("abc"); i = i + 1; }
            string output = builder.ToString();
            if (output.Length != n * 3 || builder.ByteLength() != n * 3) { return 3; }
            System.Console.WriteLine(System.Runtime.GC.GetAllocatedBytes());
            System.Console.WriteLine(output.Length);
            return 0;
        }
        if (args[0] == "concat") {
            if (n > 10000) { return 2; }
            string output = "";
            int i = 0;
            while (i < n) { output = output + "abc"; i = i + 1; }
            if (output.Length != n * 3) { return 3; }
            System.Console.WriteLine(System.Runtime.GC.GetAllocatedBytes());
            System.Console.WriteLine(output.Length);
            return 0;
        }
        if (args[0] == "utf8") {
            TextBuilder builder = new TextBuilder();
            builder.Append("A"); builder.Append("é"); builder.Append("Z");
            string output = builder.ToString();
            if (output.Length != 4 || System.Console.Utf8ByteAt(output, 0) != 65 ||
                System.Console.Utf8ByteAt(output, 1) != 195 ||
                System.Console.Utf8ByteAt(output, 2) != 169 ||
                System.Console.Utf8ByteAt(output, 3) != 90) { return 4; }
            System.Console.WriteLine("builder utf8 ok");
            return 0;
        }
        return 2;
    }
}
