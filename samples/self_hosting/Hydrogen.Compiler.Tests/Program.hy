using Hydrogen.Compiler.Binding;
using Hydrogen.Compiler.CodeGen.X64;
using Hydrogen.Compiler.Core;
using Hydrogen.Compiler.Diagnostics;
using Hydrogen.Compiler.IR;
using Hydrogen.Compiler.RuntimeModel;
using Hydrogen.Compiler.Syntax;
using Hydrogen.Compiler.Text;
using System.Testing;

namespace Hydrogen.Compiler.Tests {
    public class Program {
        private static string FindRepoPath(string relativePath) {
            if (System.IO.File.Exists(relativePath)) {
                return relativePath;
            }

            string prefix = "../";
            int i = 0;
            while (i < 8) {
                string candidate = prefix + relativePath;
                if (System.IO.File.Exists(candidate)) {
                    return candidate;
                }
                prefix = prefix + "../";
                i = i + 1;
            }

            return relativePath;
        }

        private static bool Contains(string text, string needle) {
            int i = 0;
            while (i <= text.Length - needle.Length) {
                int j = 0;
                bool match = true;
                while (j < needle.Length) {
                    if (text[i + j] != needle[j]) {
                        match = false;
                    }
                    j = j + 1;
                }
                if (match) {
                    return true;
                }
                i = i + 1;
            }
            return false;
        }

        private static long Read32(byte[] bytes, int offset) {
            return bytes[offset] + bytes[offset + 1] * 256 +
                bytes[offset + 2] * 65536 + (long)bytes[offset + 3] * 16777216;
        }

        private static bool ContainsByte(byte[] bytes, int start, int value) {
            int i = start;
            while (i < bytes.Length) { if (bytes[i] == (byte)value) { return true; } i = i + 1; }
            return false;
        }

        public static int Main(string[] args) {
            SyntaxTree hello = SyntaxTree.Parse(new SourceText("public class Program { public static void Main(string[] args) { System.Console.WriteLine(\"Hello\"); } }"));
            Assert.Equal("Public", SyntaxFacts.KindName(hello.Tokens().Get(0).Kind()), "first token should be public");
            Assert.Equal("EndOfFile", SyntaxFacts.KindName(hello.Tokens().Get(hello.Tokens().Count() - 1).Kind()), "last token should be EOF");
            Assert.True(hello.ParseText().Length > 0, "parse output should not be empty");

            SyntaxTree generic = SyntaxTree.Parse(new SourceText("public class Box<T> { private T value; public T Value() { return value; } }"));
            Assert.True(generic.Diagnostics().Count() != 0, "generic class should report diagnostics in self-host subset");

            SyntaxTree stateful = SyntaxTree.ParseFast(new SourceText("public class State { private int counter = 3; private string name; public State(string input) { name = input; } }"));
            Assert.True(stateful.Diagnostics().Count() == 0, "stateful class should parse without diagnostics");
            ClassDeclarationSyntax statefulClass = stateful.Root().Classes()[0];
            Assert.True(statefulClass.Fields().Length == 2, "self-host AST must preserve fields");
            Assert.Equal("counter", statefulClass.Fields()[0].Name(), "first field name should be retained");
            Assert.True(statefulClass.Fields()[0].Initializer() != null, "field initializer should be retained");
            Assert.True(statefulClass.Methods().Length == 1, "constructor should be retained as a method");
			SyntaxTree construction = SyntaxTree.ParseFast(new SourceText("public class Program { public static void Main(string[] args) { State value = new State(42); } }"));
			StatementSyntax constructionStatement = construction.Root().Classes()[0].Methods()[0].Body().Statements()[0];
			ExpressionSyntax constructionExpression = constructionStatement.Initializer();
			Assert.True(constructionExpression.Arguments().Length == 1, "object creation arguments should be retained");

            SyntaxTree unsafeTree = SyntaxTree.Parse(new SourceText("public class P { public static void Main(string[] args) { unsafe { byte* ptr = stackalloc byte[4]; ptr[0] = 1; } } }"));
            Assert.True(unsafeTree.ParseText().Length > 0, "unsafe tree should produce parse text");

            SyntaxTree broken = SyntaxTree.Parse(new SourceText("public class Broken { public void M( { return; }"));
            Assert.True(broken.Diagnostics().Count() != 0, "broken source should report diagnostics");

            TinyProgramBinder binder = new TinyProgramBinder();
            BindResult bind = binder.Bind(hello);
            Assert.True(bind.Success(), "tiny WriteLine program should bind");
            Assert.Equal("Hello", bind.Program().Message(), "bound IR should preserve the WriteLine literal");
            Assert.True(bind.Program().ExitCode() == 0, "missing return should default to zero");

            SyntaxTree returns = SyntaxTree.Parse(new SourceText("public class Program { public static int Main(string[] args) { System.Console.WriteLine(\"First\"); System.Console.WriteLine(\"Second\"); return 7; } }"));
            BindResult returnBind = binder.Bind(returns);
            Assert.True(returnBind.Success(), "tiny program with return should bind");
            Assert.Equal("First\nSecond", returnBind.Program().Message(), "native IR should preserve multiple WriteLine literals");
            Assert.True(returnBind.Program().ExitCode() == 7, "native IR should preserve integer return code");

            ElfImageBuilder builder = new ElfImageBuilder();
            byte[] image = builder.BuildWriteLineProgram(new IrProgram("Hello", 0));
            Assert.True(image.Length > 166, "ELF image should contain headers, code, and text");
            Assert.True(image[0] == (byte)0x7f, "ELF magic byte 0 should be valid");
            Assert.True(image[1] == (byte)0x45, "ELF magic byte 1 should be valid");
            Assert.True(image[2] == (byte)0x4c, "ELF magic byte 2 should be valid");
            Assert.True(image[3] == (byte)0x46, "ELF magic byte 3 should be valid");

            NativeRuntimeContract runtime = new NativeRuntimeContract();
            Assert.Equal("linux-x64-elf phase6c-managed-runtime", runtime.Describe(), "runtime model should name the native target");

            NativeCompiler nativeCompiler = new NativeCompiler();
            NativeCompilerResult helloCheck = nativeCompiler.CheckFileEmitIr(FindRepoPath("tests/phase6/native_hello.hy"));
            Assert.True(helloCheck.Success(), "native_hello should check");
            Assert.True(Contains(helloCheck.DiagnosticsText(), "WriteLineLiteral(\"Hydrogen native hello\")"), "native_hello should lower WriteLineLiteral");

            NativeCompilerResult returnCheck = nativeCompiler.CheckFileEmitIr(FindRepoPath("tests/phase6/native_return.hy"));
            Assert.True(returnCheck.Success(), "native_return should check");
            Assert.True(Contains(returnCheck.DiagnosticsText(), "WriteLineLiteral(\"First native line\")"), "native_return should lower first WriteLineLiteral");
            Assert.True(Contains(returnCheck.DiagnosticsText(), "WriteLineLiteral(\"Second native line\")"), "native_return should lower second WriteLineLiteral");
            Assert.True(Contains(returnCheck.DiagnosticsText(), "Exit(7)"), "native_return should lower Exit(7)");

            string execSource = "public class Program { public static void Main(string[] args) { " +
                "System.Australis.Terminal.Write(\"user> \"); " +
                "System.Australis.Terminal.ReadLine(64); " +
                "System.Australis.Terminal.WriteResult(); " +
                "System.Australis.Files.Open(\"/hello.txt\"); " +
                "System.Australis.Files.Read(1024); " +
                "System.Australis.Terminal.WriteResult(); " +
                "System.Australis.Files.Close(); } }";
            SyntaxTree execTree = SyntaxTree.ParseFast(new SourceText(execSource));
            DiagnosticBag execDiagnostics = new DiagnosticBag();
            BoundProgram execProgram = new Hydrogen.Compiler.Binding.Binder().Bind(execTree.Root(), execDiagnostics);
            Assert.True(!execDiagnostics.HasErrors(), "Australis intrinsics should bind");
            byte[] execImage = new AustralisExecImageBuilder().Build(execProgram);
            Assert.True(execImage != null && execImage.Length > 32, "Australis backend should emit an image");
            Assert.True(execImage[0] == 65 && execImage[1] == 85 && execImage[2] == 69 &&
                execImage[3] == 88 && execImage[4] == 1 && execImage[5] == 32,
                "Australis image should have an AUEX v1 header");
            Assert.True(Read32(execImage, 12) == 16 && Read32(execImage, 16) == 1040,
                "Australis backend should allocate literals and the largest read buffer");
            Assert.True(execImage[32] == 2 && execImage[41] == 3,
                "Australis backend should emit write then terminal read opcodes");

            string portableExecSource = "public class Program { public static int Main(string[] args) { " +
                "System.Console.Write(\"user> \"); " +
                "string input = System.Console.ReadLine(); " +
                "System.Console.WriteLine(input); " +
                "if (!System.IO.File.Exists(\"/hello.txt\")) { return 2; } " +
                "string contents = System.IO.File.ReadAllText(\"/hello.txt\"); " +
                "System.IO.File.WriteAllText(\"/data/new\", contents); " +
                "if (System.Convert.ToInt32(\"42\") != 42) { return 3; } " +
                "System.Console.Write(contents); return 0; } }";
            SyntaxTree portableExecTree = SyntaxTree.ParseFast(new SourceText(portableExecSource));
            DiagnosticBag portableExecDiagnostics = new DiagnosticBag();
            BoundProgram portableExecProgram = new Hydrogen.Compiler.Binding.Binder().Bind(
                portableExecTree.Root(), portableExecDiagnostics);
            Assert.True(!portableExecDiagnostics.HasErrors(),
                "portable console and file intrinsics should bind");
            byte[] portableExecImage = new AustralisExecImageBuilder().Build(portableExecProgram);
            Assert.True(portableExecImage != null && Read32(portableExecImage, 16) == 65536,
                "portable Australis strings should reserve checked result storage");
            Assert.True(ContainsByte(portableExecImage, 32, 56) &&
                ContainsByte(portableExecImage, 32, 57) &&
                ContainsByte(portableExecImage, 32, 58) &&
                ContainsByte(portableExecImage, 32, 59),
                "portable Australis program should emit shared console, file, and conversion calls");

            string advancedExecSource = "public class Program { public static int Helper() { return 3; } " +
                "public static int Main(string[] args) { " +
                "int total = 0; for (int i = 0; i < 8; i = i + 1) { " +
                "if (i % 2 == 0) { continue; } total = total + i; " +
                "if (total > 10) { break; } } while (total < 20) { total = total + 2; } " +
                "System.Console.WriteLine(total); return total; } }";
            SyntaxTree advancedExecTree = SyntaxTree.ParseFast(new SourceText(advancedExecSource));
            DiagnosticBag advancedExecDiagnostics = new DiagnosticBag();
            BoundProgram advancedExecProgram = new Hydrogen.Compiler.Binding.Binder().Bind(
                advancedExecTree.Root(), advancedExecDiagnostics);
            Assert.True(!advancedExecDiagnostics.HasErrors(), "structured Australis program should bind");
            byte[] advancedExecImage = new AustralisExecImageBuilder().Build(advancedExecProgram);
            Assert.True(advancedExecImage != null && advancedExecImage.Length > 64,
                "Australis backend should emit arithmetic and loop bytecode");
            Assert.True(ContainsByte(advancedExecImage, 32, 19) &&
                ContainsByte(advancedExecImage, 32, 28) && ContainsByte(advancedExecImage, 32, 32),
                "Australis bytecode should include modulo, conditional branch, and scalar output");

            DirectMainCompiler directMain = new DirectMainCompiler();
            SyntaxTree directTree = SyntaxTree.ParseFast(new SourceText("public class Program { public static int Main(string[] args) { int x = 1; if (x == 1) { System.Console.WriteLine(\"x was 1\"); return 7; } System.Console.WriteLine(\"x was not 1\"); return 3; } }"));
            DirectImageResult directImage = directMain.Compile(new Hydrogen.Compiler.Binding.Binder().Bind(directTree.Root(), new DiagnosticBag()).Module());
            Assert.True(directImage.Success(), "direct backend should lower locals, comparison, if, WriteLine, and return");
            Assert.True(directImage.Image().Length > 200, "direct backend image should include generated code and rodata");
            DirectImageResult missingEntry = directMain.CompileFreestanding(
                new Hydrogen.Compiler.Binding.Binder().Bind(directTree.Root(), new DiagnosticBag()).Module(),
                "Missing", "Run", false);
            Assert.True(!missingEntry.Success() &&
                missingEntry.Message() == "missing freestanding entry method Missing.Run",
                "direct backend must report compilation failures instead of returning partial code");

            ProjectClosure cliClosure = ProjectClosure.Collect(FindRepoPath("samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj"));
            string[] projects = cliClosure.Projects();
            Assert.True(projects.Length == 7, "CLI closure should contain 7 projects");
            Assert.True(Contains(projects[0], "Hydrogen.Compiler.Core.hyproj"), "closure[0] should be Core");
            Assert.True(Contains(projects[1], "Hydrogen.Compiler.Syntax.hyproj"), "closure[1] should be Syntax");
            Assert.True(Contains(projects[2], "Hydrogen.Compiler.IR.hyproj"), "closure[2] should be IR");
            Assert.True(Contains(projects[3], "Hydrogen.Compiler.Binding.hyproj"), "closure[3] should be Binding");
            Assert.True(Contains(projects[4], "Hydrogen.Compiler.RuntimeModel.hyproj"), "closure[4] should be RuntimeModel");
            Assert.True(Contains(projects[5], "Hydrogen.Compiler.CodeGen.X64.hyproj"), "closure[5] should be CodeGen");
            Assert.True(Contains(projects[6], "Hydrogen.Compiler.Cli.hyproj"), "closure[6] should be CLI");

            string[] closureSources = cliClosure.Sources();
            int cs = 0;
            while (cs < closureSources.Length) {
                SyntaxTree parsed = SyntaxTree.Parse(SourceText.FromFile(FindRepoPath(closureSources[cs])));
                if (parsed.Diagnostics().Count() != 0) {
                    System.Console.WriteLine("CLI closure source should parse without diagnostics: " + closureSources[cs]);
                    System.Console.Write(parsed.Diagnostics().ToText());
                    return 1;
                }
                cs = cs + 1;
            }

            ProjectClosure cycle = ProjectClosure.Collect(FindRepoPath("tests/phase6/cycle_a.hyproj"));
            Assert.True(Contains(cycle.Projects()[0], "<cycle:"), "cycle detection should produce a cycle marker");

            System.Console.WriteLine("phase6-self-hosting-foundation-ok");
            return 0;
        }
    }
}
