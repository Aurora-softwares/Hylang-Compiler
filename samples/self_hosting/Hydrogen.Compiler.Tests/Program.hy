using Hydrogen.Compiler.Binding;
using Hydrogen.Compiler.CodeGen.X64;
using Hydrogen.Compiler.Diagnostics;
using Hydrogen.Compiler.IR;
using Hydrogen.Compiler.RuntimeModel;
using Hydrogen.Compiler.Syntax;
using Hydrogen.Compiler.Text;
using System.Testing;

namespace Hydrogen.Compiler.Tests {
    public class Program {
        public static int Main(string[] args) {
            SyntaxTree hello = SyntaxTree.Parse(new SourceText("public class Program { public static void Main(string[] args) { System.Console.WriteLine(\"Hello\"); } }"));
            Assert.Equal("Public", SyntaxFacts.KindName(hello.Tokens().Get(0).Kind()), "first token should be public");
            Assert.Equal("EndOfFile", SyntaxFacts.KindName(hello.Tokens().Get(hello.Tokens().Count() - 1).Kind()), "last token should be EOF");
            Assert.True(hello.ParseText().Length > 0, "parse output should not be empty");

            SyntaxTree generic = SyntaxTree.Parse(new SourceText("public class Box<T> { private T value; public T Value() { return value; } }"));
            Assert.True(generic.Diagnostics().Count() == 0, "generic class should parse without diagnostics");

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
            Assert.Equal("linux-x64-elf phase6a-tiny", runtime.Describe(), "runtime model should name the native target");

            System.Console.WriteLine("phase6-self-hosting-foundation-ok");
            return 0;
        }
    }
}
