using System;
using System.IO;

namespace TokenDump {
    public class Program {
        public static int Main(string[] args) {
            if (args.Length != 1) {
                Console.WriteLine("usage: token_dump <input.hy>");
                return 1;
            }

            string path = args[0];
            if (!File.Exists(path)) {
                Console.Write("missing file: ");
                Console.WriteLine(path);
                return 1;
            }

            string source = File.ReadAllText(path);
            Scanner scanner = new Scanner(source);
            while (true) {
                Token token = scanner.NextToken();
                token.Print();
                if (token.Kind == TokenKind.EndOfFile) {
                    break;
                }
            }

            return 0;
        }
    }
}
