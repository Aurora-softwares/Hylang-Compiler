using HexLab.Core;

public class Program {
    public static int Main(string[] args) {
        if (args.Length < 2) {
            Usage();
            return 1;
        }

        string command = args[0];
        if (command == "dump") {
            int width = 16;
            int start = 0;
            int count = -1;
            if (args.Length >= 3) {
                width = System.Convert.ToInt32(args[2]);
            }
            if (args.Length >= 4) {
                start = System.Convert.ToInt32(args[3]);
            }
            if (args.Length >= 5) {
                count = System.Convert.ToInt32(args[4]);
            }
            System.Console.WriteLine(HexLab.DumpFile(args[1], width, start, count));
            return 0;
        }

        if (command == "inspect") {
            System.Console.WriteLine(HexLab.InspectFile(args[1]));
            return 0;
        }

        if (command == "diff") {
            if (args.Length < 3) {
                Usage();
                return 1;
            }
            System.Console.WriteLine(HexLab.DiffFiles(args[1], args[2]));
            return 0;
        }

        if (command == "search") {
            if (args.Length < 3) {
                Usage();
                return 1;
            }
            System.Console.WriteLine(HexLab.SearchFile(args[1], args[2]));
            return 0;
        }

        if (command == "slice") {
            if (args.Length < 5) {
                Usage();
                return 1;
            }
            int start = System.Convert.ToInt32(args[2]);
            int count = System.Convert.ToInt32(args[3]);
            System.Console.WriteLine(HexLab.SliceFile(args[1], start, count, args[4]));
            return 0;
        }

        Usage();
        return 1;
    }

    public static void Usage() {
        System.Console.WriteLine("usage: hexlab dump <file> [width] [start] [count]");
        System.Console.WriteLine("   or: hexlab inspect <file>");
        System.Console.WriteLine("   or: hexlab diff <left> <right>");
        System.Console.WriteLine("   or: hexlab search <file> <hex-pattern>");
        System.Console.WriteLine("   or: hexlab slice <file> <start> <count> <out>");
    }
}
