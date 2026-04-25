using Hydrogen.Compiler.Binding;
using Hydrogen.Compiler.Syntax;
using Hydrogen.Compiler.Text;

namespace Hydrogen.Compiler.CodeGen.X64 {
    public class NativeCompilerResult {
        private bool success;
        private string diagnosticsText;

        public NativeCompilerResult(bool inputSuccess, string inputDiagnosticsText) {
            success = inputSuccess;
            diagnosticsText = inputDiagnosticsText;
        }

        public bool Success() {
            return success;
        }

        public string DiagnosticsText() {
            return diagnosticsText;
        }
    }

    public class NativeCompiler {
        public NativeCompilerResult CompileFile(string inputPath, string outputPath) {
            SourceText source = SourceText.FromFile(inputPath);
            SyntaxTree tree = SyntaxTree.Parse(source);
            TinyProgramBinder binder = new TinyProgramBinder();
            BindResult bind = binder.Bind(tree);
            if (!bind.Success()) {
                return new NativeCompilerResult(false, bind.Diagnostics().ToText());
            }

            ElfImageBuilder builder = new ElfImageBuilder();
            byte[] image = builder.BuildWriteLineProgram(bind.Program());
            System.IO.File.WriteAllBytes(outputPath, image);
            return new NativeCompilerResult(true, "");
        }

        public NativeCompilerResult CheckFile(string inputPath) {
            SourceText source = SourceText.FromFile(inputPath);
            SyntaxTree tree = SyntaxTree.Parse(source);
            TinyProgramBinder binder = new TinyProgramBinder();
            BindResult bind = binder.Bind(tree);
            if (!bind.Success()) {
                return new NativeCompilerResult(false, bind.Diagnostics().ToText());
            }
            return new NativeCompilerResult(true, bind.Program().ToDebugText());
        }
    }
}
