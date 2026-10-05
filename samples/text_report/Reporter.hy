using System;
using System.IO;

namespace TextReport {
    public class Reporter {
        public void Run(string inputPath, string outputPath) {
            Console.Write("Scanning ");
            Console.WriteLine(inputPath);

            if (!File.Exists(inputPath)) {
                Console.WriteLine("Missing input file");
                return;
            }

            string contents = File.ReadAllText(inputPath);
            string summary = ReportFormatter.BuildSummary(contents);
            File.WriteAllText(outputPath, summary);

            Console.Write("Report written: ");
            Console.WriteLine(outputPath);
            Console.WriteLine(summary);
        }
    }
}
