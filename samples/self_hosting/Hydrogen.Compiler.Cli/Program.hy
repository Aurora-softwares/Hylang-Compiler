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

			// The first argument is always the command, so we branch on that.
            string command = args[0];
            if (command == "new") {
                return New(args);
            }

			// From here the commands need a second argument
            if (args.Length < 2) {
                PrintUsage();
                return 1;
            }
            if (command == "stage-compare") {
                return StageCompare(args);
            }

			// From here the commands need a file path to operate on, so we check for existence of the file.
            string path = args[1];
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

			// If we reach here, the command was not recognized, so we print usage and return an error code.
            PrintUsage();
            return 1;
        }

        private static int New(string[] args) {
            if (args.Length != 3) {
                System.Console.WriteLine("usage: hy new app|lib|tool|test|workspace|os|efi|kernel <name>");
                return 1;
            }
            string kind = args[1];
            string destination = PathUtils.Normalize(args[2]);
            if (kind != "app" && kind != "lib" && kind != "tool" && kind != "test" && kind != "workspace" && kind != "os" && kind != "efi" && kind != "kernel") {
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
            if (kind == "os") {
                string osPath = PathUtils.Join(destination, name + ".hyproj");
                System.IO.File.WriteAllText(osPath, RenderManifest(name, "os", "", false));
                return 0;
            }

            string projectType = "exe";
            string sourceFile = "Program.hy";
            if (kind == "lib") {
                projectType = "lib";
                sourceFile = "Library.hy";
            } else if (kind == "test") {
                projectType = "test";
            } else if (kind == "efi" || kind == "kernel") {
                projectType = kind;
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
            } else if (type == "os") {
                text = text + "project_references = []\n";
            } else {
                if (type == "efi") {
                    text = text + "output = \"EFI/" + name + ".EFI\"\n";
                } else if (type == "kernel") {
                    text = text + "output = \"EFI/KERNEL.EFI\"\n";
                }
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
            if (EndsWith(path, ".hyproj")) {
                HyprojManifest manifest = HyprojManifest.Load(path);
                if (manifest.Type() == "os") {
                    return ProcessOsProject(path, manifest, "", true, emitIr);
                }
            }
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
                System.Console.WriteLine("usage: hy build <project.hyproj> -o <output-file|output-directory>");
                return 1;
            }
            if (args[2] != "-o") {
                System.Console.WriteLine("usage: hy build <project.hyproj> -o <output-file|output-directory>");
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
            if (manifest.Type() == "os") {
                return ProcessOsProject(projectPath, manifest, args[3], false, false);
            }
            if (manifest.Type() != "exe" && manifest.Type() != "efi" && manifest.Type() != "kernel") {
                System.Console.WriteLine("error: hy build supports exe, efi, kernel, and os projects");
                return 1;
            }

            NativeCompiler compiler = new NativeCompiler();
            NativeCompilerResult result;
            if (manifest.Type() == "exe") { result = compiler.BuildProject(projectPath, args[3]); }
            else { result = compiler.BuildProjectUefi(projectPath, args[3]); }
            if (!result.Success()) {
                System.Console.Write(result.DiagnosticsText());
                return 1;
            }
            System.Console.WriteLine("wrote " + args[3]);
            return 0;
        }

        private static int ProcessOsProject(string projectPath, HyprojManifest manifest, string outputDirectory, bool check, bool emitIr) {
            if (manifest.Format() != 2) {
                System.Console.WriteLine("error: unsupported OS project format (expected format = 2)");
                return 1;
            }
            string[] references = manifest.ProjectReferences();
            if (manifest.Sources().Length != 0 || references.Length == 0) {
                System.Console.WriteLine("error: OS projects require project_references and no sources");
                return 1;
            }

            string[] paths = new string[references.Length];
            string[] outputs = new string[references.Length];
            int i = 0;
            while (i < references.Length) {
                string path = PathUtils.Join(PathUtils.DirName(projectPath), references[i]);
                if (!System.IO.File.Exists(path)) {
                    System.Console.WriteLine("error: referenced project not found: " + path);
                    return 1;
                }
                HyprojManifest child = HyprojManifest.Load(path);
                if (child.Format() != 2 || (child.Type() != "exe" && child.Type() != "efi" && child.Type() != "kernel")) {
                    System.Console.WriteLine("error: OS reference must be a format 2 exe, efi, or kernel project: " + path);
                    return 1;
                }
                string output = child.Output();
                if (!ValidOsOutput(output)) {
                    System.Console.WriteLine("error: OS project output must be a relative path below the output directory: " + path);
                    return 1;
                }
                output = PathUtils.Normalize(output);
                int previous = 0;
                while (previous < i) {
                    if (outputs[previous] == output) {
                        System.Console.WriteLine("error: duplicate OS output path: " + output);
                        return 1;
                    }
                    previous = previous + 1;
                }
                paths[i] = path;
                outputs[i] = output;
                i = i + 1;
            }

            NativeCompiler compiler = new NativeCompiler();
            int index = 0;
            while (index < paths.Length) {
                string outputPath = PathUtils.Join(outputDirectory, outputs[index]);
                NativeCompilerResult result;
                if (check) {
                    if (emitIr) { result = compiler.CheckFileEmitIr(paths[index]); }
                    else { result = compiler.CheckFile(paths[index]); }
                } else {
                    result = compiler.BuildProjectUefi(paths[index], outputPath);
                }
                if (!result.Success()) {
                    System.Console.Write(result.DiagnosticsText());
                    return 1;
                }
                if (check) {
                    System.Console.WriteLine("check ok: " + paths[index]);
                    if (emitIr) { System.Console.WriteLine(result.DiagnosticsText()); }
                } else {
                    System.Console.WriteLine("wrote " + outputPath);
                }
                index = index + 1;
            }
            return 0;
        }

        private static bool ValidOsOutput(string output) {
            if (output == "" || output[0] == "/" || output[0] == "\\") { return false; }
            string normalized = PathUtils.Normalize(output);
            return normalized != "." && normalized != ".." && !StartsWith(normalized, "../");
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

        private static bool EndsWith(string text, string suffix) {
            if (text.Length < suffix.Length) { return false; }
            int i = 0;
            while (i < suffix.Length) {
                if (text[text.Length - suffix.Length + i] != suffix[i]) { return false; }
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
            System.Console.WriteLine("usage: hy new app|lib|tool|test|workspace|os|efi|kernel <name>");
            System.Console.WriteLine("usage: hy <tokens|parse|check|build> <file.hy|project.hyproj>");
            System.Console.WriteLine("usage: hy check <file.hy> --emit-ir");
            System.Console.WriteLine("usage: hy compile <file.hy> -o <output>");
            System.Console.WriteLine("usage: hy compile <file.hy> --target uefi-x64 -o <output>");
            System.Console.WriteLine("usage: hy build <project.hyproj> -o <output-file|output-directory>");
            System.Console.WriteLine("usage: hy stage-compare <project.hyproj> --stage1 <path> --stage2 <path>");
        }
    }
}
