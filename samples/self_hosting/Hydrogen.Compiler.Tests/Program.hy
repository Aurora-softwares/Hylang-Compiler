using Hydrogen.Compiler.Diagnostics;
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

            System.Console.WriteLine("phase5-self-hosting-ok");
            return 0;
        }
    }
}
