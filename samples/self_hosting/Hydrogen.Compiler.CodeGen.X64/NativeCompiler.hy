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
        private BuildProgress progress;

        public void SetBuildProgress(BuildProgress value) {
            progress = value;
        }

        public NativeCompilerResult BuildProject(string projectPath, string outputPath) {
            return ProcessProject(projectPath, outputPath, false, false, false, false, false, false, false);
        }

        public NativeCompilerResult BuildProjectUefi(string projectPath, string outputPath) {
            return ProcessProject(projectPath, outputPath, false, false, true, false, false, false, false);
        }

        public NativeCompilerResult BuildProjectKernel(string projectPath, string outputPath) {
            return ProcessProject(projectPath, outputPath, false, false, false, true, false, false, false);
        }

        public NativeCompilerResult BuildProjectAustralis(string projectPath, string outputPath) {
			return ProcessProject(projectPath, outputPath, false, false, false, false, true, false, false);
		}

        public NativeCompilerResult BuildProjectNativeUser(string projectPath, string outputPath) {
            return ProcessProject(projectPath, outputPath, false, false, false, false, false, true, false);
        }
        
        public NativeCompilerResult BuildProjectWindows(string projectPath, string outputPath) {
            return ProcessProject(projectPath, outputPath, false, false, false, false, false, false, true);
        }

        public NativeCompilerResult CheckProjectAustralis(string projectPath, bool emitIr) {
            return ProcessProject(projectPath, "", true, emitIr, false, false, true, false, false);
        }

        public NativeCompilerResult CheckProjectNativeUser(string projectPath, bool emitIr) {
            return ProcessProject(projectPath, "", true, emitIr, false, false, false, true, false);
        }

        public NativeCompilerResult CheckProjectWindows(string projectPath, bool emitIr) {
            return ProcessProject(projectPath, "", true, emitIr, false, false, false, false, true);
        }

        private NativeCompilerResult ProcessProject(string projectPath, string outputPath, bool check, bool emitIr, bool uefi, bool kernel, bool australis, bool nativeUser, bool windows) {
            ProjectClosure closure = ProjectClosure.Collect(projectPath);
            string[] projects = closure.Projects();
            if (projects.Length == 1 && StartsWith(projects[0], "<cycle:")) {
                return new NativeCompilerResult(false, "error: project reference cycle detected at " + projects[0] + "\n");
            }

            string[] sources = closure.Sources();
            if (sources.Length == 0) {
                return new NativeCompilerResult(false, "error: project has no sources\n");
            }
            if (progress != null && !check) {
                int steps = sources.Length * 3 + 4;
                if (uefi || kernel || australis || nativeUser || windows) { steps = sources.Length * 3 + 3; }
                progress.Start(projectPath, steps);
            }

            // Keep only syntax roots after each file has passed parsing. Token
            // lists and source buffers are not needed by executable lowering.
            CompilationUnitSyntax[] units = new CompilationUnitSyntax[sources.Length];
            int i = 0;
            while (i < sources.Length) {
                if (progress != null && !check) { progress.Begin("Reading " + sources[i]); }
                SourceText source = SourceText.FromFile(sources[i]);
                DiagnosticBag subsetDiagnostics = new DiagnosticBag();
                SelfHostSubsetValidator subset = new SelfHostSubsetValidator();
                if (!subset.Validate(source, subsetDiagnostics)) {
                    return new NativeCompilerResult(false, sources[i] + ":\n" + subsetDiagnostics.ToText());
                }

                SyntaxTree tree;
                if (progress != null && !check) {
                    tree = SyntaxTree.ParseFastWithProgress(source, progress, sources[i]);
                } else {
                    tree = SyntaxTree.ParseFast(source);
                }
                if (tree.Diagnostics().HasErrors()) {
                    return new NativeCompilerResult(false, sources[i] + ":\n" + tree.Diagnostics().ToText());
                }
                units[i] = tree.Root();
                if (progress != null && !check) { progress.Step("Parsed " + sources[i]); }
                i = i + 1;
                // Parsed roots remain in units; the temporary lexer and
                // source buffers from earlier files can be reclaimed here.
                System.Runtime.GC.Collect();
            }

            DiagnosticBag diagnostics = new DiagnosticBag();
            Hydrogen.Compiler.Binding.Binder binder = new Hydrogen.Compiler.Binding.Binder();
            if (progress != null && !check) { progress.Begin("Binding program"); }
            BoundProgram program = binder.BindUnits(units, diagnostics);
            // Bound executable IR owns its nodes; the AST closure can be released
            // before native code/data buffers are allocated.
            units = new CompilationUnitSyntax[0];
            System.Runtime.GC.Collect();
            if (diagnostics.HasErrors()) {
                return new NativeCompilerResult(false, projectPath + ":\n" + diagnostics.ToText());
            }
            if (progress != null && !check) { progress.Step("Bound program"); }

            if (check) {
                if (australis || nativeUser) {
                    byte[] validated = null;
                    if (nativeUser) {
                        validated = new AustralisNativeImageBuilder().Build(program);
                    } else {
                        validated = new AustralisExecImageBuilder().Build(program);
                    }
                    if (validated == null) {
                        return new NativeCompilerResult(false,
                            projectPath + ": unsupported Australis program for this target\n");
                    }
                }
                if (windows) {
                    IrModule lowered = new IrLowering().Lower(program);
                    DirectImageResult validatedWindows = new DirectMainCompiler().CompileWindows(lowered);
                    if (!validatedWindows.Success()) {
                        return new NativeCompilerResult(false,
                            projectPath + ": error: Windows x64 compilation failed: " + validatedWindows.Message() + "\n");
                    }
                }
                return new NativeCompilerResult(true, DebugProgram(program, emitIr));
            }
            if (kernel) { return EmitKernelImage(program, projectPath, outputPath); }
            if (uefi) { return EmitUefiImage(program, projectPath, outputPath); }
			if (australis) { return EmitAustralisImage(program, projectPath, outputPath); }
            if (nativeUser) { return EmitNativeUserImage(program, projectPath, outputPath); }
            if (windows) { return EmitWindowsImage(program, projectPath, outputPath); }
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

        public NativeCompilerResult CompileFileWindows(string inputPath, string outputPath) {
            SourceText source = SourceText.FromFile(inputPath);

            DiagnosticBag subsetDiagnostics = new DiagnosticBag();
            SelfHostSubsetValidator subset = new SelfHostSubsetValidator();

            if (!subset.Validate(source, subsetDiagnostics)) {
                return new NativeCompilerResult(
                    false,
                    inputPath + ":\n" + subsetDiagnostics.ToText()
                );
            }

            SyntaxTree tree = SyntaxTree.ParseFast(source);

            if (tree.Diagnostics().HasErrors()) {
                return new NativeCompilerResult(
                    false,
                    inputPath + ":\n" + tree.Diagnostics().ToText()
                );
            }

            DiagnosticBag diagnostics = new DiagnosticBag();

            Hydrogen.Compiler.Binding.Binder binder =
                new Hydrogen.Compiler.Binding.Binder();

            BoundProgram program = binder.Bind(
                tree.Root(),
                diagnostics
            );

            if (diagnostics.HasErrors()) {
                return new NativeCompilerResult(
                    false,
                    inputPath + ":\n" + diagnostics.ToText()
                );
            }

            return EmitWindowsImage(
                program,
                inputPath,
                outputPath
            );
        }

        private NativeCompilerResult EmitNativeImage(BoundProgram program, string inputPath, string outputPath) {
            DirectMainCompiler direct = new DirectMainCompiler();
            if (progress != null) {
                progress.Begin("Lowering program");
                direct.SetBuildProgress(progress);
            }
            IrLowering lowering = new IrLowering();
            IrModule lowered = lowering.Lower(program);
            if (progress != null) { progress.Begin("Compiling native image"); }
            DirectImageResult result = direct.Compile(lowered);
            if (!result.Success()) {
                return new NativeCompilerResult(false, inputPath + ": error: native compilation failed: " + result.Message() + "\n");
            }
            if (progress != null) { progress.Step("Generated native image"); }

            // Write only after the entire entrypoint has compiled successfully.
            // Unsupported code must never become a partial program or an IR-debug ELF.
            if (progress != null) { progress.Begin("Writing " + outputPath); }
            System.IO.File.WriteAllBytes(outputPath, result.Image());
            if (progress != null) { progress.Step("Wrote " + outputPath); }
            return new NativeCompilerResult(true, "");
        }

        private NativeCompilerResult EmitUefiImage(BoundProgram program, string inputPath, string outputPath) {
            if (progress != null) { progress.Begin("Generating UEFI image"); }
            IrLowering lowering = new IrLowering();
            IrEntryPoint entryPoint = lowering.LowerEntryPoint(program);
            byte[] kernelCode = new byte[0];
            IrOp[] ops = entryPoint.Ops();
            bool rawKernelLoad = false;
            int i = 0;
            while (i < ops.Length) {
                if (ops[i].Kind() == IrOp.KindLoadRawKernelLiteral()) { rawKernelLoad = true; }
                i = i + 1;
            }
            i = 0;
            while (i < ops.Length) {
                if (ops[i].Kind() == IrOp.KindExecuteKernel() && !rawKernelLoad) {
                    DirectMainCompiler direct = new DirectMainCompiler();
                    if (progress != null) { direct.SetBuildProgress(progress); }
                    DirectImageResult compiled = direct.CompileFreestanding(lowering.Lower(program), "KernelMain", "Run");
                    if (!compiled.Success()) {
                        return new NativeCompilerResult(false, inputPath + ": error: freestanding kernel compilation failed: " + compiled.Message() + "\n");
                    }
                    kernelCode = compiled.Image();
                    break;
                }
                i = i + 1;
            }
            UefiImageBuilder builder = new UefiImageBuilder();
            UefiImageResult result = builder.Build(entryPoint, kernelCode);
            if (!result.Success()) {
                return new NativeCompilerResult(false, inputPath + ": error: UEFI compilation failed: " + result.Message() + "\n");
            }
            if (progress != null) { progress.Step("Generated UEFI image"); }
            if (progress != null) { progress.Begin("Writing " + outputPath); }
            System.IO.File.WriteAllBytes(outputPath, result.Image());
            if (progress != null) { progress.Step("Wrote " + outputPath); }
            return new NativeCompilerResult(true, "");
        }

		private NativeCompilerResult EmitAustralisImage(BoundProgram program, string inputPath, string outputPath) {
			if (progress != null) { progress.Begin("Generating Australis image"); }
			AustralisExecImageBuilder builder = new AustralisExecImageBuilder();
			byte[] executable = builder.Build(program);
			if (executable == null) {
				return new NativeCompilerResult( false, inputPath + ": unsupported Australis program\n");
			}
			if (progress != null) { progress.Step("Generated Australis image"); }
			if (progress != null) { progress.Begin("Writing " + outputPath); }
			System.IO.File.WriteAllBytes(outputPath, executable);
			if (progress != null) { progress.Step("Wrote " + outputPath); }
			return new NativeCompilerResult(true, "");
		}

        private NativeCompilerResult EmitNativeUserImage(BoundProgram program, string inputPath, string outputPath) {
            if (progress != null) { progress.Begin("Generating AUN1 image"); }
            byte[] image = new AustralisNativeImageBuilder().Build(program);
            if (image == null) {
                return new NativeCompilerResult(false, inputPath + ": unsupported AUN1 v2 program\n");
            }
            if (progress != null) { progress.Step("Generated AUN1 image"); }
            if (progress != null) { progress.Begin("Writing " + outputPath); }
            System.IO.File.WriteAllBytes(outputPath, image);
            if (progress != null) { progress.Step("Wrote " + outputPath); }
            return new NativeCompilerResult(true, "");
        }

        // AUKR v1: 16-byte header followed by raw position-independent code.
        // The loader validates size and entry offset before ending boot services.
        private NativeCompilerResult EmitKernelImage(BoundProgram program, string inputPath, string outputPath) {
            if (progress != null) { progress.Begin("Generating kernel image"); }
            IrLowering lowering = new IrLowering();
            DirectMainCompiler direct = new DirectMainCompiler();
            if (progress != null) { direct.SetBuildProgress(progress); }
            DirectImageResult compiled = direct.CompileFreestanding(lowering.Lower(program), "KernelMain", "Run");
            if (!compiled.Success()) {
                return new NativeCompilerResult(false, inputPath + ": error: kernel compilation failed: " + compiled.Message() + "\n");
            }
            byte[] code = compiled.Image();
            if (code.Length == 0 || code.Length > 1048560) {
                return new NativeCompilerResult(false, inputPath + ": error: kernel code exceeds the 1 MiB loader limit\n");
            }
            byte[] image = new byte[16 + code.Length];
            image[0] = (byte)65; image[1] = (byte)85; image[2] = (byte)75; image[3] = (byte)82;
            image[4] = (byte)1; // version
            int length = code.Length;
            int i = 0;
            while (i < 4) {
                image[8 + i] = (byte)(length % 256);
                length = length / 256;
                i = i + 1;
            }
            image[12] = (byte)16; // entry offset
            i = 0;
            while (i < code.Length) { image[16 + i] = code[i]; i = i + 1; }
            if (progress != null) { progress.Step("Generated kernel image"); }
            if (progress != null) { progress.Begin("Writing " + outputPath); }
            System.IO.File.WriteAllBytes(outputPath, image);
            if (progress != null) { progress.Step("Wrote " + outputPath); }
            return new NativeCompilerResult(true, "");
        }

        private NativeCompilerResult EmitWindowsImage(BoundProgram program, string inputPath, string outputPath) {
            IrLowering lowering = new IrLowering();
            IrModule module = lowering.Lower(program);
            DirectMainCompiler direct = new DirectMainCompiler();
            if (progress != null) { direct.SetBuildProgress(progress); progress.Begin("Compiling Windows image"); }
            DirectImageResult result = direct.CompileWindows(module);
            if (!result.Success()) {
                return new NativeCompilerResult(false, inputPath + ": error: Windows x64 compilation failed: " + result.Message() + "\n");
            }
            if (progress != null) { progress.Step("Generated Windows image"); progress.Begin("Writing " + outputPath); }
            System.IO.File.WriteAllBytes(outputPath, result.Image());
            if (progress != null) { progress.Step("Wrote " + outputPath); }
            return new NativeCompilerResult(true, "");
        }

        public NativeCompilerResult CheckFile(string inputPath) {
            return CheckFileInternal(inputPath, false);
        }

        public NativeCompilerResult CheckFileEmitIr(string inputPath) {
            return CheckFileInternal(inputPath, true);
        }

        private NativeCompilerResult CheckFileInternal(string inputPath, bool emitIr) {
            if (IsProject(inputPath)) { return ProcessProject(inputPath, "", true, emitIr, false, false, false, false, false); }
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
