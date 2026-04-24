using SdkDemo.Core;

public class Program {
    public static int Main(string[] args) {
        if (args.Length != 1) {
            System.Console.WriteLine("usage: sdkdemo <input.txt>");
            return 1;
        }
        if (!System.IO.File.Exists(args[0])) {
            System.Console.WriteLine("missing file");
            return 1;
        }
        string text = System.IO.File.ReadAllText(args[0]);
        System.Console.WriteLine(Report.FromText(text));
        return 0;
    }
}
