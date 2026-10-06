using Hydrogen.Compiler.CodeGen.X64;
using Hydrogen.Compiler.Core;
using Hydrogen.Compiler.Diagnostics;
using Hydrogen.Compiler.Syntax;
using Hydrogen.Compiler.Text;

namespace Hydrogen.Compiler.Cli {
    public class Program {
        public static int Main(string[] args) {
            if (args.Length < 1) {
                PrintUsage();
                return 1;
            }

            string command = args[0];
            if (command == "new") {
                return New(args);
            }
            if (args.Length < 2) {
                PrintUsage();
                return 1;
            }
            string path = args[1];
            if (command == "stage-compare") {
                return StageCompare(args);
            }
            if (!System.IO.File.Exists(path)) {
                System.Console.WriteLine("error: file not found");
                return 1;
            }

            if (command == "tokens") {
                // Token dump should be lexer-only (no AST parser diagnostics), for stable golden output.
                SourceText source = SourceText.FromFile(path);
                DiagnosticBag diagnostics = new DiagnosticBag();
                Lexer lexer = new Lexer(source, diagnostics);
                SyntaxTokenList tokens = lexer.LexAll();
                int ti = 0;
                while (ti < tokens.Count()) {
                    System.Console.WriteLine(tokens.Get(ti).ToLine());
                    ti = ti + 1;
                }
                return 0;
            }
            if (command == "parse") {
                // Parse dump is the outline parser only (no AST parser diagnostics), for stable golden output.
                SourceText source2 = SourceText.FromFile(path);
                DiagnosticBag diagnostics2 = new DiagnosticBag();
                Lexer lexer2 = new Lexer(source2, diagnostics2);
                SyntaxTokenList tokens2 = lexer2.LexAll();
                Parser parser2 = new Parser(tokens2, diagnostics2);
                System.Console.Write(parser2.ParseCompilationUnit());
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

        private static int New(string[] args) {
            if (args.Length != 3) {
                System.Console.WriteLine("usage: hy new app|lib|tool|test|workspace <name>");
                return 1;
            }
            string kind = args[1];
            string destination = PathUtils.Normalize(args[2]);
            if (kind != "app" && kind != "lib" && kind != "tool" && kind != "test" && kind != "workspace") {
                System.Console.WriteLine("error: unknown project kind '" + kind + "'");
                return 1;
            }
            if (System.IO.File.Exists(destination)) {
                System.Console.WriteLine("destination already exists: " + destination);
                return 1;
            }

            string name = PathUtils.BaseName(destination);
            if (kind == "workspace") {
                string workspacePath = PathUtils.Join(destination, name + ".hyproj");
                string workspaceManifest = RenderManifest(name, "workspace", "", true);
                System.IO.File.WriteAllText(workspacePath, workspaceManifest);
                return 0;
            }

            string projectType = "exe";
            string sourceFile = "Program.hy";
            if (kind == "lib") {
                projectType = "lib";
                sourceFile = "Library.hy";
            } else if (kind == "test") {
                projectType = "test";
            }
            string manifestPath = PathUtils.Join(destination, name + ".hyproj");
            string manifestText = RenderManifest(name, projectType, sourceFile, false);
            System.IO.File.WriteAllText(manifestPath, manifestText);
            string sourcePath = PathUtils.Join(destination, sourceFile);
            string sourceText = RenderSource(kind, name);
            System.IO.File.WriteAllText(sourcePath, sourceText);
            return 0;
        }

        private static string RenderManifest(string name, string type, string source, bool workspace) {
            string text = "format = 2\n";
            text = text + "name = \"" + name + "\"\n";
            text = text + "version = \"0.1.0\"\n";
            text = text + "type = \"" + type + "\"\n";
            if (workspace) {
                text = text + "members = []\n";
            } else {
                text = text + "sources = [\"" + source + "\"]\n";
                text = text + "project_references = []\n";
            }
            text = text + "\n[package]\n";
            text = text + "id = \"" + name + "\"\n";
            text = text + "description = \"\"\n";
            text = text + "authors = []\n";
            text = text + "license = \"\"\n";
            return text;
        }

        private static string RenderSource(string kind, string name) {
            if (kind == "lib") {
                return "namespace " + name + " {\n" +
                    "    public class Library {\n" +
                    "        public static string Name() {\n" +
                    "            return \"" + name + "\";\n" +
                    "        }\n" +
                    "    }\n" +
                    "}\n";
            }
            if (kind == "test") {
                return "using System.Testing;\n\n" +
                    "public class Program {\n" +
                    "    public static int Main(string[] args) {\n" +
                    "        Assert.True(true, \"scaffolded test should pass\");\n" +
                    "        return 0;\n" +
                    "    }\n" +
                    "}\n";
            }
            return "public class Program {\n" +
                "    public static void Main(string[] args) {\n" +
                "        System.Console.WriteLine(\"Hello from " + name + "!\");\n" +
                "    }\n" +
                "}\n";
        }

        private static int Check(string path, bool emitIr) {
            NativeCompiler compiler = new NativeCompiler();
            if (emitIr) {
                NativeCompilerResult result = compiler.CheckFileEmitIr(path);
                if (!result.Success()) {
                    System.Console.Write(result.DiagnosticsText());
                    return 1;
                }
                System.Console.WriteLine("check ok");
                System.Console.WriteLine(result.DiagnosticsText());
                return 0;
            } else {
                NativeCompilerResult result2 = compiler.CheckFile(path);
                if (!result2.Success()) {
                    System.Console.Write(result2.DiagnosticsText());
                    return 1;
                }
                System.Console.WriteLine("check ok");
                System.Console.WriteLine(result2.DiagnosticsText());
                return 0;
            }
        }

        private static int Compile(string[] args) {
            bool uefi = false;
            string output = "";
            if (args.Length == 4 && args[2] == "-o") {
                output = args[3];
            } else if (args.Length == 6 && args[2] == "--target" && args[3] == "uefi-x64" && args[4] == "-o") {
                uefi = true;
                output = args[5];
            } else {
                System.Console.WriteLine("usage: hy compile <file.hy> -o <output>");
                System.Console.WriteLine("   or: hy compile <file.hy> --target uefi-x64 -o <output>");
                return 1;
            }

            NativeCompiler compiler = new NativeCompiler();
            NativeCompilerResult result;
            if (uefi) { result = compiler.CompileFileUefi(args[1], output); }
            else { result = compiler.CompileFile(args[1], output); }
            if (!result.Success()) {
                System.Console.Write(result.DiagnosticsText());
                return 1;
            }
            System.Console.WriteLine("wrote " + output);
            return 0;
        }

        private static int Build(string[] args) {
            if (args.Length != 4) {
                System.Console.WriteLine("usage: hy build <project.hyproj> -o <output>");
                return 1;
            }
            if (args[2] != "-o") {
                System.Console.WriteLine("usage: hy build <project.hyproj> -o <output>");
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
                System.Console.WriteLine("error: only type = \"exe\" is supported by hy build in this phase");
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

            // Artifact comparison is one part of the bootstrap proof. The
            // proof driver separately rebuilds the compiler and runs its corpus.
            byte[] first = System.IO.File.ReadAllBytes(stage1Path);
            byte[] second = System.IO.File.ReadAllBytes(stage2Path);
            if (first.Length != second.Length) {
                System.Console.WriteLine("stage artifacts differ in length: " + first.Length + " vs " + second.Length);
                return 1;
            }
            int i = 0;
            while (i < first.Length) {
                if (first[i] != second[i]) {
                    System.Console.WriteLine("stage artifacts differ at byte " + i);
                    return 1;
                }
                i = i + 1;
            }
            System.Console.WriteLine("stage artifacts match (" + first.Length + " bytes)");
            return 0;
        }

        private static void PrintUsage() {
            System.Console.WriteLine("usage: hy new app|lib|tool|test|workspace <name>");
            System.Console.WriteLine("usage: hy <tokens|parse|check|build> <file.hy|project.hyproj>");
            System.Console.WriteLine("usage: hy check <file.hy> --emit-ir");
            System.Console.WriteLine("usage: hy compile <file.hy> -o <output>");
            System.Console.WriteLine("usage: hy compile <file.hy> --target uefi-x64 -o <output>");
            System.Console.WriteLine("usage: hy build <project.hyproj> -o <output>");
            System.Console.WriteLine("usage: hy stage-compare <project.hyproj> --stage1 <path> --stage2 <path>");
        }
    }
}
