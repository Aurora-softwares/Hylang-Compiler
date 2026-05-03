using Hydrogen.Compiler.Binding;
using Hydrogen.Compiler.Diagnostics;
using Hydrogen.Compiler.Core;
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
            ProjectClosure closure = ProjectClosure.Collect(projectPath);
            string[] projects = closure.Projects();
            if (projects.Length == 1 && StartsWith(projects[0], "<cycle:")) {
                return new NativeCompilerResult(false, "error: project reference cycle detected at " + projects[0] + "\n");
            }

            string[] sources = closure.Sources();
            if (sources.Length == 0) {
                return new NativeCompilerResult(false, "error: project has no sources\n");
            }

            SyntaxTree[] trees = new SyntaxTree[sources.Length];
            int i = 0;
            while (i < sources.Length) {
                SourceText source = SourceText.FromFile(sources[i]);
                DiagnosticBag subsetDiagnostics = new DiagnosticBag();
                SelfHostSubsetValidator subset = new SelfHostSubsetValidator();
                if (!subset.Validate(source, subsetDiagnostics)) {
                    return new NativeCompilerResult(false, subsetDiagnostics.ToText());
                }
                SyntaxTree tree = SyntaxTree.ParseFast(source);
                if (tree.Diagnostics().HasErrors()) {
                    return new NativeCompilerResult(false, sources[i] + ":\n" + tree.Diagnostics().ToText());
                }
                trees[i] = tree;
                i = i + 1;
            }

            CompilationUnitSyntax merged = MergeCompilationUnits(trees);
            DiagnosticBag diagnostics = new DiagnosticBag();
            Hydrogen.Compiler.Binding.Binder binder = new Hydrogen.Compiler.Binding.Binder();
            BoundProgram program = binder.Bind(merged, diagnostics);
            if (diagnostics.HasErrors()) {
                return new NativeCompilerResult(false, diagnostics.ToText());
            }
            if (program.EntryOps().Length == 0) {
                return new NativeCompilerResult(false, "error: no supported entry point for native compilation in this phase\n");
            }

            Hydrogen.Compiler.IR.IrLowering lowering = new Hydrogen.Compiler.IR.IrLowering();
            Hydrogen.Compiler.IR.IrEntryPoint entryPoint = lowering.LowerEntryPoint(program);

            ElfImageBuilder builder = new ElfImageBuilder();
            byte[] image = builder.BuildEntryPoint(entryPoint);
            System.IO.File.WriteAllBytes(outputPath, image);
            return new NativeCompilerResult(true, "");
        }

        public NativeCompilerResult CompileFile(string inputPath, string outputPath) {
            SourceText source = SourceText.FromFile(inputPath);
            DiagnosticBag subsetDiagnostics = new DiagnosticBag();
            SelfHostSubsetValidator subset = new SelfHostSubsetValidator();
            if (!subset.Validate(source, subsetDiagnostics)) {
                return new NativeCompilerResult(false, subsetDiagnostics.ToText());
            }
            SyntaxTree tree = SyntaxTree.ParseFast(source);
            if (tree.Diagnostics().HasErrors()) {
                return new NativeCompilerResult(false, inputPath + ":\n" + tree.Diagnostics().ToText());
            }

            DiagnosticBag diagnostics = new DiagnosticBag();
            Hydrogen.Compiler.Binding.Binder binder = new Hydrogen.Compiler.Binding.Binder();
            BoundProgram program = binder.Bind(tree.Root(), diagnostics);
            if (diagnostics.HasErrors()) {
                return new NativeCompilerResult(false, diagnostics.ToText());
            }
            if (program.EntryOps().Length == 0) {
                return new NativeCompilerResult(false, "error: no supported entry point for native compilation in this phase\n");
            }

            Hydrogen.Compiler.IR.IrLowering lowering = new Hydrogen.Compiler.IR.IrLowering();
            Hydrogen.Compiler.IR.IrEntryPoint entryPoint = lowering.LowerEntryPoint(program);

            ElfImageBuilder builder = new ElfImageBuilder();
            byte[] image = builder.BuildEntryPoint(entryPoint);
            System.IO.File.WriteAllBytes(outputPath, image);
            return new NativeCompilerResult(true, "");
        }

        public NativeCompilerResult CheckFile(string inputPath) {
            return CheckFileInternal(inputPath, false);
        }

        public NativeCompilerResult CheckFileEmitIr(string inputPath) {
            return CheckFileInternal(inputPath, true);
        }

        private NativeCompilerResult CheckFileInternal(string inputPath, bool emitIr) {
            SourceText source = SourceText.FromFile(inputPath);
            DiagnosticBag subsetDiagnostics = new DiagnosticBag();
            SelfHostSubsetValidator subset = new SelfHostSubsetValidator();
            if (!subset.Validate(source, subsetDiagnostics)) {
                return new NativeCompilerResult(false, subsetDiagnostics.ToText());
            }
            SyntaxTree tree = SyntaxTree.ParseFast(source);
            if (tree.Diagnostics().HasErrors()) {
                return new NativeCompilerResult(false, inputPath + ":\n" + tree.Diagnostics().ToText());
            }

            DiagnosticBag diagnostics = new DiagnosticBag();
            Hydrogen.Compiler.Binding.Binder binder = new Hydrogen.Compiler.Binding.Binder();
            BoundProgram program = binder.Bind(tree.Root(), diagnostics);
            if (diagnostics.HasErrors()) {
                return new NativeCompilerResult(false, diagnostics.ToText());
            }

            string text = program.ToDebugText();
            if (emitIr) {
                Hydrogen.Compiler.IR.IrLowering lowering = new Hydrogen.Compiler.IR.IrLowering();
                Hydrogen.Compiler.IR.IrEntryPoint entryPoint = lowering.LowerEntryPoint(program);
                text = text + entryPoint.ToDebugText();
            }
            return new NativeCompilerResult(true, text);
        }

        private CompilationUnitSyntax MergeCompilationUnits(SyntaxTree[] trees) {
            UsingDirectiveSyntax[] usings = new UsingDirectiveSyntax[0];
            int usingCount = 0;
            NamespaceDeclarationSyntax[] namespaces = new NamespaceDeclarationSyntax[0];
            int namespaceCount = 0;
            ClassDeclarationSyntax[] classes = new ClassDeclarationSyntax[0];
            int classCount = 0;

            int i = 0;
            while (i < trees.Length) {
                CompilationUnitSyntax root = trees[i].Root();

                UsingDirectiveSyntax[] u = root.Usings();
                int ui = 0;
                while (ui < u.Length) {
                    usings = AppendUsing(usings, usingCount, u[ui]);
                    usingCount = usingCount + 1;
                    ui = ui + 1;
                }

                NamespaceDeclarationSyntax[] n = root.Namespaces();
                int ni = 0;
                while (ni < n.Length) {
                    namespaces = AppendNamespace(namespaces, namespaceCount, n[ni]);
                    namespaceCount = namespaceCount + 1;
                    ni = ni + 1;
                }

                ClassDeclarationSyntax[] c = root.Classes();
                int ci = 0;
                while (ci < c.Length) {
                    classes = AppendClass(classes, classCount, c[ci]);
                    classCount = classCount + 1;
                    ci = ci + 1;
                }

                i = i + 1;
            }

            return new CompilationUnitSyntax(usings, namespaces, classes);
        }

        private UsingDirectiveSyntax[] AppendUsing(UsingDirectiveSyntax[] items, int count, UsingDirectiveSyntax item) {
            UsingDirectiveSyntax[] next = new UsingDirectiveSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private NamespaceDeclarationSyntax[] AppendNamespace(NamespaceDeclarationSyntax[] items, int count, NamespaceDeclarationSyntax item) {
            NamespaceDeclarationSyntax[] next = new NamespaceDeclarationSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }

        private ClassDeclarationSyntax[] AppendClass(ClassDeclarationSyntax[] items, int count, ClassDeclarationSyntax item) {
            ClassDeclarationSyntax[] next = new ClassDeclarationSyntax[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
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
