using Hydrogen.Compiler.Binding;
using Hydrogen.Compiler.Core;
using Hydrogen.Compiler.Diagnostics;
using Hydrogen.Compiler.IR;
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
        public NativeCompilerResult BuildProject(string projectPath, string outputPath) {
            return ProcessProject(projectPath, outputPath, false, false, false);
        }

        public NativeCompilerResult BuildProjectUefi(string projectPath, string outputPath) {
            return ProcessProject(projectPath, outputPath, false, false, true);
        }

        private NativeCompilerResult ProcessProject(string projectPath, string outputPath, bool check, bool emitIr, bool uefi) {
            ProjectClosure closure = ProjectClosure.Collect(projectPath);
            string[] projects = closure.Projects();
            if (projects.Length == 1 && StartsWith(projects[0], "<cycle:")) {
                return new NativeCompilerResult(false, "error: project reference cycle detected at " + projects[0] + "\n");
            }

            string[] sources = closure.Sources();
            if (sources.Length == 0) {
                return new NativeCompilerResult(false, "error: project has no sources\n");
            }

            // Keep only syntax roots after each file has passed parsing. Token
            // lists and source buffers are not needed by executable lowering.
            CompilationUnitSyntax[] units = new CompilationUnitSyntax[sources.Length];
            int i = 0;
            while (i < sources.Length) {
                SourceText source = SourceText.FromFile(sources[i]);
                DiagnosticBag subsetDiagnostics = new DiagnosticBag();
                SelfHostSubsetValidator subset = new SelfHostSubsetValidator();
                if (!subset.Validate(source, subsetDiagnostics)) {
                    return new NativeCompilerResult(false, sources[i] + ":\n" + subsetDiagnostics.ToText());
                }

                SyntaxTree tree = SyntaxTree.ParseFast(source);
                if (tree.Diagnostics().HasErrors()) {
                    return new NativeCompilerResult(false, sources[i] + ":\n" + tree.Diagnostics().ToText());
                }
                units[i] = tree.Root();
                i = i + 1;
            }

            DiagnosticBag diagnostics = new DiagnosticBag();
            Hydrogen.Compiler.Binding.Binder binder = new Hydrogen.Compiler.Binding.Binder();
            BoundProgram program = binder.BindUnits(units, diagnostics);
            // Bound executable IR owns its nodes; the AST closure can be released
            // before native code/data buffers are allocated.
            units = new CompilationUnitSyntax[0];
            if (diagnostics.HasErrors()) {
                return new NativeCompilerResult(false, projectPath + ":\n" + diagnostics.ToText());
            }

            if (check) { return new NativeCompilerResult(true, DebugProgram(program, emitIr)); }
            if (uefi) { return EmitUefiImage(program, projectPath, outputPath); }
            return EmitNativeImage(program, projectPath, outputPath);
        }

        public NativeCompilerResult CompileFile(string inputPath, string outputPath) {
            SourceText source = SourceText.FromFile(inputPath);
            DiagnosticBag subsetDiagnostics = new DiagnosticBag();
            SelfHostSubsetValidator subset = new SelfHostSubsetValidator();
            if (!subset.Validate(source, subsetDiagnostics)) {
                return new NativeCompilerResult(false, inputPath + ":\n" + subsetDiagnostics.ToText());
            }
            SyntaxTree tree = SyntaxTree.ParseFast(source);
            if (tree.Diagnostics().HasErrors()) {
                return new NativeCompilerResult(false, inputPath + ":\n" + tree.Diagnostics().ToText());
            }

            DiagnosticBag diagnostics = new DiagnosticBag();
            Hydrogen.Compiler.Binding.Binder binder = new Hydrogen.Compiler.Binding.Binder();
            BoundProgram program = binder.Bind(tree.Root(), diagnostics);
            if (diagnostics.HasErrors()) {
                return new NativeCompilerResult(false, inputPath + ":\n" + diagnostics.ToText());
            }

            return EmitNativeImage(program, inputPath, outputPath);
        }

        public NativeCompilerResult CompileFileUefi(string inputPath, string outputPath) {
            SourceText source = SourceText.FromFile(inputPath);
            DiagnosticBag subsetDiagnostics = new DiagnosticBag();
            SelfHostSubsetValidator subset = new SelfHostSubsetValidator();
            if (!subset.Validate(source, subsetDiagnostics)) {
                return new NativeCompilerResult(false, inputPath + ":\n" + subsetDiagnostics.ToText());
            }
            SyntaxTree tree = SyntaxTree.ParseFast(source);
            if (tree.Diagnostics().HasErrors()) {
                return new NativeCompilerResult(false, inputPath + ":\n" + tree.Diagnostics().ToText());
            }

            DiagnosticBag diagnostics = new DiagnosticBag();
            Hydrogen.Compiler.Binding.Binder binder = new Hydrogen.Compiler.Binding.Binder();
            BoundProgram program = binder.Bind(tree.Root(), diagnostics);
            if (diagnostics.HasErrors()) {
                return new NativeCompilerResult(false, inputPath + ":\n" + diagnostics.ToText());
            }

            return EmitUefiImage(program, inputPath, outputPath);
        }

        private NativeCompilerResult EmitNativeImage(BoundProgram program, string inputPath, string outputPath) {
            DirectMainCompiler direct = new DirectMainCompiler();
            IrLowering lowering = new IrLowering();
            DirectImageResult result = direct.Compile(lowering.Lower(program));
            if (!result.Success()) {
                return new NativeCompilerResult(false, inputPath + ": error: native compilation failed: " + result.Message() + "\n");
            }

            // Write only after the entire entrypoint has compiled successfully.
            // Unsupported code must never become a partial program or an IR-debug ELF.
            System.IO.File.WriteAllBytes(outputPath, result.Image());
            return new NativeCompilerResult(true, "");
        }

        private NativeCompilerResult EmitUefiImage(BoundProgram program, string inputPath, string outputPath) {
            IrLowering lowering = new IrLowering();
            UefiImageBuilder builder = new UefiImageBuilder();
            UefiImageResult result = builder.Build(lowering.LowerEntryPoint(program));
            if (!result.Success()) {
                return new NativeCompilerResult(false, inputPath + ": error: UEFI compilation failed: " + result.Message() + "\n");
            }
            System.IO.File.WriteAllBytes(outputPath, result.Image());
            return new NativeCompilerResult(true, "");
        }

        public NativeCompilerResult CheckFile(string inputPath) {
            return CheckFileInternal(inputPath, false);
        }

        public NativeCompilerResult CheckFileEmitIr(string inputPath) {
            return CheckFileInternal(inputPath, true);
        }

        private NativeCompilerResult CheckFileInternal(string inputPath, bool emitIr) {
            if (IsProject(inputPath)) { return ProcessProject(inputPath, "", true, emitIr, false); }
            SourceText source = SourceText.FromFile(inputPath);
            DiagnosticBag subsetDiagnostics = new DiagnosticBag();
            SelfHostSubsetValidator subset = new SelfHostSubsetValidator();
            if (!subset.Validate(source, subsetDiagnostics)) {
                return new NativeCompilerResult(false, inputPath + ":\n" + subsetDiagnostics.ToText());
            }
            SyntaxTree tree = SyntaxTree.ParseFast(source);
            if (tree.Diagnostics().HasErrors()) {
                return new NativeCompilerResult(false, inputPath + ":\n" + tree.Diagnostics().ToText());
            }

            DiagnosticBag diagnostics = new DiagnosticBag();
            Hydrogen.Compiler.Binding.Binder binder = new Hydrogen.Compiler.Binding.Binder();
            BoundProgram program = binder.Bind(tree.Root(), diagnostics);
            if (diagnostics.HasErrors()) {
                return new NativeCompilerResult(false, inputPath + ":\n" + diagnostics.ToText());
            }

            return new NativeCompilerResult(true, DebugProgram(program, emitIr));
        }

        private string DebugProgram(BoundProgram program, bool emitIr) {
            string text = program.ToDebugText();
            if (emitIr) {
                Hydrogen.Compiler.IR.IrLowering lowering = new Hydrogen.Compiler.IR.IrLowering();
                Hydrogen.Compiler.IR.IrEntryPoint entryPoint = lowering.LowerEntryPoint(program);
                text = text + entryPoint.ToDebugText() + lowering.Lower(program).ToDebugText();
            }
            return text;
        }

        private bool IsProject(string path) {
            string suffix = ".hyproj";
            if (path.Length < suffix.Length) { return false; }
            int i = 0;
            while (i < suffix.Length) { if (path[path.Length - suffix.Length + i] != suffix[i]) { return false; } i = i + 1; }
            return true;
        }

        private bool StartsWith(string text, string prefix) {
            if (text.Length < prefix.Length) { return false; }
            int i = 0;
            while (i < prefix.Length) {
                if (text[i] != prefix[i]) { return false; }
                i = i + 1;
            }
            return true;
        }
    }
}
