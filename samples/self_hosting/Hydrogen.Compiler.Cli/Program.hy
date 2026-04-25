using Hydrogen.Compiler.CodeGen.X64;
using Hydrogen.Compiler.Syntax;
using Hydrogen.Compiler.Text;

namespace Hydrogen.Compiler.Cli {
    public class Program {
        public static int Main(string[] args) {
            if (args.Length < 2) {
                PrintUsage();
                return 1;
            }

            string command = args[0];
            string path = args[1];
            if (command == "stage-compare") {
                return StageCompare(args);
            }
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
            if (command == "check") {
                return Check(path);
            }
            if (command == "compile") {
                return Compile(args);
            }

            PrintUsage();
            return 1;
        }

        private static int Check(string path) {
            NativeCompiler compiler = new NativeCompiler();
            NativeCompilerResult result = compiler.CheckFile(path);
            if (!result.Success()) {
                System.Console.Write(result.DiagnosticsText());
                return 1;
            }
            System.Console.WriteLine("check ok");
            System.Console.WriteLine(result.DiagnosticsText());
            return 0;
        }

        private static int Compile(string[] args) {
            if (args.Length != 4 || args[2] != "-o") {
                System.Console.WriteLine("usage: hydrogen-compiler compile <file.hy> -o <output>");
                return 1;
            }

            NativeCompiler compiler = new NativeCompiler();
            NativeCompilerResult result = compiler.CompileFile(args[1], args[3]);
            if (!result.Success()) {
                System.Console.Write(result.DiagnosticsText());
                return 1;
            }
            System.Console.WriteLine("wrote " + args[3]);
            return 0;
        }

        private static int StageCompare(string[] args) {
            if (args.Length != 6) {
                PrintUsage();
                return 1;
            }
            System.Console.WriteLine("stage-compare requires the Phase 6E stage1/stage2 compiler artifacts");
            System.Console.WriteLine("status: interface reserved, full self-host comparison not complete yet");
            return 1;
        }

        private static void PrintUsage() {
            System.Console.WriteLine("usage: hydrogen-compiler <tokens|parse|check> <file.hy>");
            System.Console.WriteLine("usage: hydrogen-compiler compile <file.hy> -o <output>");
            System.Console.WriteLine("usage: hydrogen-compiler stage-compare <project.hyproj> --stage1 <path> --stage2 <path>");
        }
    }
}
