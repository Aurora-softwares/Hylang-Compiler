using Hydrogen.Compiler.CodeGen.X64;
using Hydrogen.Compiler.Core;
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
                bool emitIr = false;
                if (args.Length >= 3) {
                    emitIr = args[2] == "--emit-ir";
                }
                return Check(path, emitIr);
            }
            if (command == "compile") {
                return Compile(args);
            }
            if (command == "build") {
                return Build(args);
            }

            PrintUsage();
            return 1;
        }

        private static int Check(string path, bool emitIr) {
            NativeCompiler compiler = new NativeCompiler();
            NativeCompilerResult result = compiler.CheckFile(path);
            if (emitIr) {
                result = compiler.CheckFileEmitIr(path);
            }
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

        private static int Build(string[] args) {
            if (args.Length != 4 || args[2] != "-o") {
                System.Console.WriteLine("usage: hydrogen-compiler build <project.hyproj> -o <output>");
                return 1;
            }

            string projectPath = args[1];
            if (!System.IO.File.Exists(projectPath)) {
                System.Console.WriteLine("error: project file not found");
                return 1;
            }

            HyprojManifest manifest = HyprojManifest.Load(projectPath);
            if (manifest.Format() != 2) {
                System.Console.WriteLine("error: unsupported project format (expected format = 2)");
                return 1;
            }
            if (manifest.Type() != "exe") {
                System.Console.WriteLine("error: only type = \"exe\" is supported by hydrogen-compiler build in this phase");
                return 1;
            }

            NativeCompiler compiler = new NativeCompiler();
            NativeCompilerResult result = compiler.BuildProject(projectPath, args[3]);
            if (!result.Success()) {
                System.Console.Write(result.DiagnosticsText());
                return 1;
            }
            System.Console.WriteLine("wrote " + args[3]);
            return 0;
        }

        private static bool StartsWith(string text, string prefix) {
            if (text.Length < prefix.Length) { return false; }
            int i = 0;
            while (i < prefix.Length) {
                if (text[i] != prefix[i]) { return false; }
                i = i + 1;
            }
            return true;
        }

        private static int StageCompare(string[] args) {
            if (args.Length != 6) {
                PrintUsage();
                return 1;
            }

            string projectPath = args[1];
            if (args[2] != "--stage1" || args[4] != "--stage2") {
                PrintUsage();
                return 1;
            }
            string stage1Path = args[3];
            string stage2Path = args[5];

            if (!System.IO.File.Exists(projectPath)) {
                System.Console.WriteLine("error: project file not found");
                return 1;
            }
            if (!System.IO.File.Exists(stage1Path)) {
                System.Console.WriteLine("error: stage1 artifact not found");
                return 1;
            }
            if (!System.IO.File.Exists(stage2Path)) {
                System.Console.WriteLine("error: stage2 artifact not found");
                return 1;
            }

            System.Console.WriteLine("stage-compare is not implemented yet in Hydrogen (Phase 6E work item).");
            System.Console.WriteLine("inputs:");
            System.Console.WriteLine("  project: " + projectPath);
            System.Console.WriteLine("  stage1:   " + stage1Path);
            System.Console.WriteLine("  stage2:   " + stage2Path);
            System.Console.WriteLine("planned corpus (compiler-only):");
            System.Console.WriteLine("  - samples/self_hosting/Hydrogen.Compiler.Cli/Program.hy");
            System.Console.WriteLine("  - tests/phase6/native_hello.hy");
            System.Console.WriteLine("  - tests/phase6/native_return.hy");
            return 1;
        }

        private static void PrintUsage() {
            System.Console.WriteLine("usage: hydrogen-compiler <tokens|parse|check|build> <file.hy|project.hyproj>");
            System.Console.WriteLine("usage: hydrogen-compiler check <file.hy> --emit-ir");
            System.Console.WriteLine("usage: hydrogen-compiler compile <file.hy> -o <output>");
            System.Console.WriteLine("usage: hydrogen-compiler build <project.hyproj> -o <output>");
            System.Console.WriteLine("usage: hydrogen-compiler stage-compare <project.hyproj> --stage1 <path> --stage2 <path>");
        }
    }
}
