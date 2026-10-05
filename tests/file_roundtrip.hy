using System;
using System.IO;

public class Program {
    public static void Main(string[] args) {
        string inputPath = args[0];
        string outputPath = args[1];

        Console.Write("exists: ");
        Console.WriteLine(File.Exists(inputPath));

        string contents = File.ReadAllText(inputPath);
        int count = 0;
        for (int index = 0; index < contents.Length; index = index + 1) {
            count = count + 1;
        }

        string report = "chars=" + count;
        File.WriteAllText(outputPath, report);
        Console.WriteLine(report);
        Console.WriteLine(File.ReadAllText(outputPath));
    }
}
