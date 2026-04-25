using Hydrogen.Compiler.Syntax;
using Hydrogen.Compiler.Text;

namespace Hydrogen.Compiler.Cli {
    public class Program {
        public static int Main(string[] args) {
            if (args.Length != 2) {
                System.Console.WriteLine("usage: hydrogen-compiler <tokens|parse> <file.hy>");
                return 1;
            }

            string command = args[0];
            string path = args[1];
            if (!System.IO.File.Exists(path)) {
                System.Console.WriteLine("error: file not found");
                return 1;
            }

            SyntaxTree tree = SyntaxTree.Parse(SourceText.FromFile(path));
            if (command == "tokens") {
                System.Console.Write(tree.TokensText());
                return 0;
            }
            if (command == "parse") {
                System.Console.Write(tree.ParseText());
                return 0;
            }

            System.Console.WriteLine("usage: hydrogen-compiler <tokens|parse> <file.hy>");
            return 1;
        }
    }
}
