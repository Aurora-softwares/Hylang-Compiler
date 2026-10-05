using System;

namespace TextReport {
    public class Program {
        public static void Main(string[] args) {
            if (args.Length < 2) {
                Console.WriteLine("usage: text_report <input> <output>");
                return;
            }

            Reporter reporter = new Reporter();
            reporter.Run(args[0], args[1]);
        }
    }
}
