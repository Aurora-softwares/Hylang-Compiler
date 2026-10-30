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
            if (command == "package") {
                return Package(args);
            }

			// From here the commands need a second argument
            if (args.Length < 2) {
                PrintUsage();
                return 1;
            }
            if (command == "stage-compare") {
                return StageCompare(args);
            }
            if (command == "ui") {
                if (args.Length != 2) {
                    System.Console.WriteLine("usage: hy ui <file.hy|project.hyproj>");
                    return 1;
                }
                string source = QuoteCommandPath(args[1]);
                if (source == "" || (System.Host.Process.IsWindows() &&
                    (Find(args[1], "%", 0) >= 0 || Find(args[1], "!", 0) >= 0))) {
                    System.Console.WriteLine("error: unsupported UI source path");
                    return 1;
                }
                return System.Host.Process.Run("hyui --source " + source);
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
                System.Console.WriteLine("usage: hy new app|lib|tool|test|workspace|collection|os|efi|kernel|driver|exec|windows|macos <name>");
                return 1;
            }
            string kind = args[1];
            string destination = PathUtils.Normalize(args[2]);
            if (kind != "app" && kind != "lib" && kind != "tool" && kind != "test" && kind != "workspace" && kind != "collection" && kind != "os" && kind != "efi" && kind != "kernel" && kind != "driver" && kind != "exec" && kind != "windows" && kind != "macos") {
                System.Console.WriteLine("error: unknown project kind '" + kind + "'");
                return 1;
            }
            if (System.IO.File.Exists(destination)) {
                System.Console.WriteLine("destination already exists: " + destination);
                return 1;
            }
            string quotedDestination = QuoteCommandPath(destination);
            // Windows command expansion can change a quoted path containing
            // percent or delayed-expansion markers.
            if (quotedDestination == "" || (System.Host.Process.IsWindows() &&
                (Find(destination, "%", 0) >= 0 || Find(destination, "!", 0) >= 0))) {
                System.Console.WriteLine("error: invalid project destination");
                return 1;
            }
            string createCommand = "mkdir -p -- " + quotedDestination;
            if (System.Host.Process.IsWindows()) {
                createCommand = "cmd /C mkdir " + quotedDestination;
            }
            if (System.Host.Process.Run(createCommand) != 0) {
                System.Console.WriteLine("error: could not create project directory");
                return 1;
            }

            string name = PathUtils.BaseName(destination);
            if (kind == "workspace") {
                string workspacePath = PathUtils.Join(destination, name + ".hyproj");
                string workspaceManifest = RenderManifest(name, "workspace", "", true);
                System.IO.File.WriteAllText(workspacePath, workspaceManifest);
                return 0;
            }
            if (kind == "os" || kind == "collection") {
                string osPath = PathUtils.Join(destination, name + ".hyproj");
                System.IO.File.WriteAllText(osPath, RenderManifest(name, kind, "", false));
                return 0;
            }

            string projectType = "exe";
            string sourceFile = "Program.hy";
            if (kind == "lib") {
                projectType = "lib";
                sourceFile = "Library.hy";
            } else if (kind == "test") {
                projectType = "test";
            } else if (kind == "efi" || kind == "kernel" || kind == "driver" || kind == "exec" || kind == "windows" || kind == "macos") {
                projectType = kind;
                if (kind == "kernel") { sourceFile = "KernelMain.hy"; }
                if (kind == "driver") { sourceFile = "DriverMain.hy"; }
            }
            string manifestPath = PathUtils.Join(destination, name + ".hyproj");
            string manifestText = RenderManifest(name, projectType, sourceFile, false);
            System.IO.File.WriteAllText(manifestPath, manifestText);
            string sourcePath = PathUtils.Join(destination, sourceFile);
            string sourceText = RenderSource(kind, name);
            System.IO.File.WriteAllText(sourcePath, sourceText);
            return 0;
        }

        private static int Package(string[] args) {
            if (args.Length >= 3 && args[1] == "search") {
                return PackageSearch(args);
            }
            if (args.Length >= 3 && args[1] == "restore") {
                return PackageRestore(args);
            }
            if (args.Length >= 4 && args[1] == "upgrade") {
                return PackageUpgrade(args);
            }
            if (args.Length >= 4 && args[1] == "add" && Find(args[3], "@", 0) > 0) {
                return PackageRemoteAdd(args);
            }
            if (args.Length == 5 && args[1] == "pack" && args[3] == "-o") {
                return PackagePack(args);
            }
            if (args.Length == 4 && args[1] == "add") {
                return PackageAdd(args);
            }
            if (args.Length == 4 && args[1] == "remove") {
                return PackageRemove(args);
            }
            if (args.Length == 3 && args[1] == "hash") {
                if (!System.IO.File.Exists(args[2])) {
                    System.Console.WriteLine("error: file not found");
                    return 1;
                }
                System.Console.WriteLine(Sha256.Hex(System.IO.File.ReadAllBytes(args[2])));
                return 0;
            }
            if (args.Length == 3 && args[1] == "lock") {
                if (!System.IO.File.Exists(args[2]) || !EndsWith(args[2], ".hyproj")) {
                    System.Console.WriteLine("error: project file not found");
                    return 1;
                }
                ProjectClosure closure = ProjectClosure.Collect(args[2]);
                if (closure.Error() != "") {
                    System.Console.WriteLine("error: " + closure.Error());
                    return 1;
                }
                string lockText = PackageLock.Render(args[2], closure);
                if (lockText == "") {
                    System.Console.WriteLine("error: package archives or sources are missing");
                    return 1;
                }
                System.IO.File.WriteAllText(PathUtils.Join(PathUtils.DirName(args[2]), "hy.lock"), lockText);
                System.Console.WriteLine("wrote hy.lock");
                return 0;
            }
            System.Console.WriteLine("usage: hy package pack <library.hyproj> -o <output.hypkg>");
            System.Console.WriteLine("usage: hy package add <project.hyproj> <source.hypkg>");
            System.Console.WriteLine("usage: hy package remove <project.hyproj> <package-id>");
            System.Console.WriteLine("usage: hy package hash <file>");
            System.Console.WriteLine("usage: hy package lock <project.hyproj>");
            System.Console.WriteLine("usage: hy package search <term> [--registry <HTTPS-origin>]");
            System.Console.WriteLine("usage: hy package add <project.hyproj> <id@version> [--registry <HTTPS-origin>]");
            System.Console.WriteLine("usage: hy package restore <project.hyproj> [--registry <HTTPS-origin>]");
            System.Console.WriteLine("usage: hy package upgrade <project.hyproj> <id@version> [--registry <HTTPS-origin>]");
            return 1;
        }

        private static string RegistryOrigin(string[] args, int optionalAt) {
            if (args.Length == optionalAt) { return "https://hylang.co.uk/registry/v1"; }
            if (args.Length == optionalAt + 2 && args[optionalAt] == "--registry" &&
                ValidRegistryOrigin(args[optionalAt + 1])) { return args[optionalAt + 1]; }
            return "";
        }

        private static bool ValidRegistryOrigin(string origin) {
            if (!StartsWith(origin, "https://") && !StartsWith(origin, "file://")) { return false; }
            if (Find(origin, "..", 0) >= 0 || origin.Length > 512) { return false; }
            int i = 0;
            while (i < origin.Length) {
                if (Find("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:/._-", origin[i], 0) < 0) {
                    return false;
                }
                i = i + 1;
            }
            return true;
        }

        private static string QuoteCommandPath(string path) {
            if (System.Host.Process.IsWindows()) {
                if (Find(path, "\"", 0) >= 0 || Find(path, "\n", 0) >= 0) { return ""; }
                return "\"" + path + "\"";
            }
            string quoted = "'";
            int i = 0;
            while (i < path.Length) {
                if (path[i] == "'") { quoted = quoted + "'\\''"; }
                else { quoted = quoted + path[i]; }
                i = i + 1;
            }
            return quoted + "'";
        }

        private static bool DownloadRegistryFile(string origin, string relative, string output) {
            string destination = QuoteCommandPath(output);
            if (destination == "") { return false; }
            string url = origin + "/" + relative;
            string protocol = StartsWith(origin, "file://") ? "=file" : "=https";
            string command = "curl --fail --silent --show-error --location --max-time 30 " +
                "--max-filesize 16777216 --proto '" + protocol + "' --proto-redir '" + protocol + "' " +
                "--output " + destination + " " + url;
            if (System.Host.Process.IsWindows()) {
                command = "curl.exe --fail --silent --show-error --location --max-time 30 " +
                    "--max-filesize 16777216 --proto \"" + protocol + "\" --proto-redir \"" + protocol + "\" " +
                    "--output " + destination + " \"" + url + "\"";
            }
            return System.Host.Process.Run(command) == 0 && System.IO.File.Exists(output);
        }

        private static PackageRegistry LoadRegistry(string origin, string baseDir) {
            string path = PathUtils.Join(baseDir, ".hylang/registry-index.txt");
            System.IO.File.WriteAllText(path, "");
            if (!DownloadRegistryFile(origin, "index.txt", path)) {
                System.Console.WriteLine("error: cannot download package registry index");
                return PackageRegistry.Parse("");
            }
            PackageRegistry index = PackageRegistry.Parse(System.IO.File.ReadAllText(path));
            if (!index.Valid()) { System.Console.WriteLine("error: invalid package registry index"); }
            return index;
        }

        private static int PackageSearch(string[] args) {
            string origin = RegistryOrigin(args, 3);
            if (origin == "") { System.Console.WriteLine("error: invalid registry arguments"); return 1; }
            PackageRegistry index = LoadRegistry(origin, ".");
            if (!index.Valid()) { return 1; }
            int i = 0;
            while (i < index.Count()) {
                if (args[2] == "*" || Find(index.Id(i), args[2], 0) >= 0) {
                    System.Console.WriteLine(index.Id(i) + "@" + index.Version(i));
                }
                i = i + 1;
            }
            return 0;
        }

        private static bool ParsePackageSpec(string spec) {
            int at = Find(spec, "@", 0);
            if (at < 1 || Find(spec, "@", at + 1) >= 0) { return false; }
            return HyprojManifest.ValidPackagePart(Slice(spec, 0, at)) &&
                HyprojManifest.ValidPackagePart(Slice(spec, at + 1, spec.Length - at - 1));
        }

        private static string SpecId(string spec) { return Slice(spec, 0, Find(spec, "@", 0)); }
        private static string SpecVersion(string spec) {
            int at = Find(spec, "@", 0);
            return Slice(spec, at + 1, spec.Length - at - 1);
        }

        private static string FetchArchive(string projectPath, string id, string version,
            string origin, PackageRegistry index, string expectedHash) {
            string hash = index.FindHash(id, version);
            if (hash == "" || (expectedHash != "" && expectedHash != hash)) { return ""; }
            string relative = "packages/" + id + "/" + version + "/" + id + "-" + version + ".hypkg";
            string output = PathUtils.Join(PathUtils.DirName(projectPath),
                ".hylang/downloads/" + id + "-" + version + ".hypkg");
            System.IO.File.WriteAllText(output, "");
            if (!DownloadRegistryFile(origin, relative, output) ||
                Sha256.Hex(System.IO.File.ReadAllBytes(output)) != hash) { return ""; }
            return output;
        }

        private static int FetchPackageGraph(string projectPath, string id, string version,
            string origin, PackageRegistry index, string[] stack) {
            if (ContainsString(stack, id)) {
                System.Console.WriteLine("error: package dependency cycle at " + id);
                return 1;
            }
            string archive = FetchArchive(projectPath, id, version, origin, index, "");
            if (archive == "" || InstallArchive(projectPath, archive, false) != 0) {
                System.Console.WriteLine("error: cannot fetch verified package " + id + "@" + version);
                return 1;
            }
            string manifestPath = PathUtils.Join(PathUtils.DirName(projectPath),
                ".hylang/packages/" + id + "/" + version + "/" + id + ".hyproj");
            HyprojManifest manifest = HyprojManifest.Load(manifestPath);
            if (manifest.PackageId() != id || manifest.Version() != version ||
                !manifest.ValidDependencies()) { return 1; }
            string[] nextStack = AppendString(stack, id);
            string[] deps = manifest.DependencyIds();
            string[] versions = manifest.DependencyVersions();
            int i = 0;
            while (i < deps.Length) {
                if (FetchPackageGraph(projectPath, deps[i], versions[i], origin, index, nextStack) != 0) {
                    return 1;
                }
                i = i + 1;
            }
            return 0;
        }

        private static int PackageRemoteAdd(string[] args) {
            string origin = RegistryOrigin(args, 4);
            if (origin == "" || !ParsePackageSpec(args[3]) || !System.IO.File.Exists(args[2])) {
                System.Console.WriteLine("error: invalid package, project, or registry");
                return 1;
            }
            ProjectClosure prior = ProjectClosure.Collect(args[2]);
            if (prior.Error() != "" || !PackageLock.Verify(args[2], prior)) {
                System.Console.WriteLine("error: existing package graph or hy.lock is invalid");
                return 1;
            }
            string id = SpecId(args[3]);
            string version = SpecVersion(args[3]);
            PackageRegistry index = LoadRegistry(origin, PathUtils.DirName(args[2]));
            if (!index.Valid() || FetchPackageGraph(args[2], id, version, origin, index, new string[0]) != 0) {
                return 1;
            }
            string archive = PathUtils.Join(PathUtils.DirName(args[2]),
                ".hylang/downloads/" + id + "-" + version + ".hypkg");
            return InstallArchive(args[2], archive, true);
        }

        private static int PackageRestore(string[] args) {
            string origin = RegistryOrigin(args, 3);
            if (origin == "" || !System.IO.File.Exists(args[2])) {
                System.Console.WriteLine("error: invalid project or registry"); return 1;
            }
            string lockPath = PathUtils.Join(PathUtils.DirName(args[2]), "hy.lock");
            if (!System.IO.File.Exists(lockPath)) { System.Console.WriteLine("error: hy.lock is missing"); return 1; }
            string lockText = System.IO.File.ReadAllText(lockPath);
            if (!StartsWith(lockText, "hydrogen-lock-v1\n")) { return 1; }
            PackageRegistry index = LoadRegistry(origin, PathUtils.DirName(args[2]));
            if (!index.Valid()) { return 1; }
            int at = Find(lockText, "\n", 0) + 1;
            while (at < lockText.Length) {
                int end = Find(lockText, "\n", at);
                if (end < 0) { return 1; }
                string line = Slice(lockText, at, end - at);
                if (StartsWith(line, "package ")) {
                    int a = Find(line, " ", 8);
                    int b = a < 0 ? -1 : Find(line, " ", a + 1);
                    if (a < 0 || b < 0) { return 1; }
                    string id = Slice(line, 8, a - 8);
                    string version = Slice(line, a + 1, b - a - 1);
                    string hash = Slice(line, b + 1, line.Length - b - 1);
                    if (!HyprojManifest.ValidPackagePart(id) || !HyprojManifest.ValidPackagePart(version)) { return 1; }
                    string archive = FetchArchive(args[2], id, version, origin, index, hash);
                    if (archive == "" || InstallArchive(args[2], archive, false) != 0) {
                        System.Console.WriteLine("error: cannot restore verified package " + id + "@" + version);
                        return 1;
                    }
                }
                at = end + 1;
            }
            ProjectClosure closure = ProjectClosure.Collect(args[2]);
            if (closure.Error() != "" || !PackageLock.Verify(args[2], closure)) {
                System.Console.WriteLine("error: restored packages do not match hy.lock"); return 1;
            }
            System.Console.WriteLine("restored exact packages from hy.lock");
            return 0;
        }

        private static int PackageUpgrade(string[] args) {
            string origin = RegistryOrigin(args, 4);
            if (origin == "" || !ParsePackageSpec(args[3]) || !System.IO.File.Exists(args[2])) {
                System.Console.WriteLine("error: invalid package, project, or registry"); return 1;
            }
            string original = System.IO.File.ReadAllText(args[2]);
            string lockPath = PathUtils.Join(PathUtils.DirName(args[2]), "hy.lock");
            string originalLock = System.IO.File.Exists(lockPath) ? System.IO.File.ReadAllText(lockPath) : "";
            HyprojManifest project = HyprojManifest.Parse(original);
            string id = SpecId(args[3]);
            if (!ContainsString(project.DependencyIds(), id)) {
                System.Console.WriteLine("error: package is not a direct dependency: " + id); return 1;
            }
            string[] removeArgs = new string[4];
            removeArgs[0] = "package"; removeArgs[1] = "remove";
            removeArgs[2] = args[2]; removeArgs[3] = id;
            if (PackageRemove(removeArgs) != 0 || PackageRemoteAdd(args) != 0) {
                System.IO.File.WriteAllText(args[2], original);
                if (originalLock != "") { System.IO.File.WriteAllText(lockPath, originalLock); }
                System.Console.WriteLine("error: upgrade rolled back");
                return 1;
            }
            System.Console.WriteLine("upgraded " + id + " to " + SpecVersion(args[3]));
            return 0;
        }

        private static int PackagePack(string[] args) {
            string path = args[2];
            if (!System.IO.File.Exists(path) || !EndsWith(path, ".hyproj")) {
                System.Console.WriteLine("error: package project file not found");
                return 1;
            }
            HyprojManifest manifest = HyprojManifest.Load(path);
            if (manifest.Format() != 2 || manifest.Type() != "lib" ||
                !manifest.ValidDependencies() || manifest.ProjectReferences().Length != 0 ||
                !HyprojManifest.ValidPackagePart(manifest.PackageId()) ||
                !HyprojManifest.ValidPackagePart(manifest.Version()) ||
                PathUtils.BaseName(path) != manifest.PackageId() + ".hyproj") {
                System.Console.WriteLine("error: package must be a valid format 2 library");
                return 1;
            }
            string[] sources = manifest.Sources();
            string text = "HYLANG_PACKAGE_V1\n";
            string name = PathUtils.BaseName(path);
            if (!SafePackageFilename(name)) {
                System.Console.WriteLine("error: unsafe package project filename");
                return 1;
            }
            string projectText = System.IO.File.ReadAllText(path);
            text = text + "FILE " + name + " " + projectText.Length + "\n" + projectText + "\n";
            int i = 0;
            while (i < sources.Length) {
                if (!SafePackageFilename(sources[i]) || !EndsWith(sources[i], ".hy")) {
                    System.Console.WriteLine("error: package sources must be flat .hy files");
                    return 1;
                }
                string sourcePath = PathUtils.Join(PathUtils.DirName(path), sources[i]);
                if (!System.IO.File.Exists(sourcePath)) {
                    System.Console.WriteLine("error: package source not found: " + sourcePath);
                    return 1;
                }
                string sourceText = System.IO.File.ReadAllText(sourcePath);
                text = text + "FILE " + sources[i] + " " + sourceText.Length + "\n" + sourceText + "\n";
                i = i + 1;
            }
            System.IO.File.WriteAllText(args[4], text);
            System.Console.WriteLine(args[4]);
            return 0;
        }

        private static int PackageAdd(string[] args) {
            return InstallArchive(args[2], args[3], true);
        }

        private static int InstallArchive(string projectPath, string archivePath, bool direct) {
            if (!System.IO.File.Exists(projectPath) || !EndsWith(projectPath, ".hyproj") ||
                !System.IO.File.Exists(archivePath) || !EndsWith(archivePath, ".hypkg")) {
                System.Console.WriteLine("error: project or source package not found");
                return 1;
            }
            string original = System.IO.File.ReadAllText(projectPath);
            HyprojManifest project = HyprojManifest.Parse(original);
            if (project.Format() != 2 || !project.ValidDependencies()) {
                System.Console.WriteLine("error: project must be a valid format 2 manifest");
                return 1;
            }
            if (direct) {
                ProjectClosure previous = ProjectClosure.Collect(projectPath);
                if (previous.Error() != "" || !PackageLock.Verify(projectPath, previous)) {
                    System.Console.WriteLine("error: existing package graph or hy.lock is invalid");
                    return 1;
                }
            }
            string archive = System.IO.File.ReadAllText(archivePath);
            string header = "HYLANG_PACKAGE_V1\n";
            if (!StartsWith(archive, header) || archive.Length > 16777216) {
                System.Console.WriteLine("error: invalid or oversized source package");
                return 1;
            }
            string[] names = new string[0];
            string[] contents = new string[0];
            int at = header.Length;
            while (at < archive.Length) {
                if (names.Length >= 64 || !StartsWithAt(archive, "FILE ", at)) {
                    System.Console.WriteLine("error: invalid source package entry");
                    return 1;
                }
                int lineEnd = Find(archive, "\n", at);
                if (lineEnd < 0) {
                    System.Console.WriteLine("error: incomplete source package header");
                    return 1;
                }
                string line = Slice(archive, at + 5, lineEnd - at - 5);
                int separator = Find(line, " ", 0);
                if (separator < 1) {
                    System.Console.WriteLine("error: invalid source package filename");
                    return 1;
                }
                string name = Slice(line, 0, separator);
                int length = PackageLength(Slice(line, separator + 1, line.Length - separator - 1));
                if (!SafePackageFilename(name) || ContainsString(names, name) || length < 0 ||
                    length > 1048576 || lineEnd + 1 + length >= archive.Length ||
                    archive[lineEnd + 1 + length] != "\n") {
                    System.Console.WriteLine("error: unsafe source package entry");
                    return 1;
                }
                names = AppendString(names, name);
                contents = AppendString(contents, Slice(archive, lineEnd + 1, length));
                at = lineEnd + 2 + length;
            }
            if (names.Length < 2 || !EndsWith(names[0], ".hyproj")) {
                System.Console.WriteLine("error: source package has no project and sources");
                return 1;
            }
            HyprojManifest package = HyprojManifest.Parse(contents[0]);
            string id = package.PackageId();
            string version = package.Version();
            if (package.Format() != 2 || package.Type() != "lib" ||
                !package.ValidDependencies() || package.ProjectReferences().Length != 0 ||
                !HyprojManifest.ValidPackagePart(id) ||
                !HyprojManifest.ValidPackagePart(version) || names[0] != id + ".hyproj" ||
                package.Sources().Length != names.Length - 1) {
                System.Console.WriteLine("error: source package manifest does not match archive");
                return 1;
            }
            string[] sourceNames = package.Sources();
            int s = 0;
            while (s < sourceNames.Length) {
                if (names[s + 1] != sourceNames[s] || !EndsWith(names[s + 1], ".hy")) {
                    System.Console.WriteLine("error: source package file list does not match manifest");
                    return 1;
                }
                s = s + 1;
            }
            if (direct && ContainsString(project.DependencyIds(), id)) {
                System.Console.WriteLine("error: project already declares package " + id);
                return 1;
            }
            string baseDir = PathUtils.DirName(projectPath);
            string packageDir = PathUtils.Join(PathUtils.Join(PathUtils.Join(
                baseDir, ".hylang/packages"), id), version);
            bool cached = System.IO.File.Exists(PathUtils.Join(packageDir, names[0]));
            if (cached && (!System.IO.File.Exists(PathUtils.Join(packageDir, "package.hypkg")) ||
                Sha256.Hex(System.IO.File.ReadAllBytes(PathUtils.Join(packageDir, "package.hypkg"))) !=
                    Sha256.Hex(System.IO.File.ReadAllBytes(archivePath)))) {
                System.Console.WriteLine("error: cached package differs from source archive");
                return 1;
            }
            if (!cached) {
                int f = 0;
                while (f < names.Length) {
                    System.IO.File.WriteAllText(PathUtils.Join(packageDir, names[f]), contents[f]);
                    f = f + 1;
                }
                System.IO.File.WriteAllBytes(PathUtils.Join(packageDir, "package.hypkg"),
                    System.IO.File.ReadAllBytes(archivePath));
            }
            if (!direct) { return 0; }
            string updated = InsertDependency(original, id, version);
            if (updated == "") {
                System.Console.WriteLine("error: cannot update project dependencies");
                return 1;
            }
            System.IO.File.WriteAllText(projectPath, updated);
            ProjectClosure closure = ProjectClosure.Collect(projectPath);
            if (closure.Error() != "") {
                System.IO.File.WriteAllText(projectPath, original);
                System.Console.WriteLine("error: " + closure.Error());
                return 1;
            }
            string lockText = PackageLock.Render(projectPath, closure);
            if (lockText == "") {
                System.IO.File.WriteAllText(projectPath, original);
                System.Console.WriteLine("error: cannot lock installed package files");
                return 1;
            }
            System.IO.File.WriteAllText(PathUtils.Join(baseDir, "hy.lock"), lockText);
            System.Console.WriteLine("added " + id + " " + version);
            return 0;
        }

        private static string InsertDependency(string manifest, string id, string version) {
            string entry = id + " = \"" + version + "\"\n";
            int section = Find(manifest, "[dependencies]", 0);
            if (section < 0) { return manifest + "\n[dependencies]\n" + entry; }
            int newline = Find(manifest, "\n", section);
            if (newline < 0) { return manifest + "\n" + entry; }
            return Slice(manifest, 0, newline + 1) + entry +
                Slice(manifest, newline + 1, manifest.Length - newline - 1);
        }

        private static int PackageRemove(string[] args) {
            string projectPath = args[2];
            string id = args[3];
            if (!System.IO.File.Exists(projectPath) || !EndsWith(projectPath, ".hyproj") ||
                !HyprojManifest.ValidPackagePart(id)) {
                System.Console.WriteLine("error: project or package ID invalid");
                return 1;
            }
            string original = System.IO.File.ReadAllText(projectPath);
            HyprojManifest project = HyprojManifest.Parse(original);
            if (project.Format() != 2 || !project.ValidDependencies() ||
                !ContainsString(project.DependencyIds(), id)) {
                System.Console.WriteLine("error: project does not declare package " + id);
                return 1;
            }
            ProjectClosure previous = ProjectClosure.Collect(projectPath);
            if (previous.Error() != "" || !PackageLock.Verify(projectPath, previous)) {
                System.Console.WriteLine("error: existing package graph or hy.lock is invalid");
                return 1;
            }
            string updated = "";
            string section = "";
            int at = 0;
            bool removed = false;
            while (at < original.Length) {
                int end = Find(original, "\n", at);
                if (end < 0) { end = original.Length; }
                string line = Slice(original, at, end - at);
                string trimmed = TrimSpaces(line);
                if (StartsWith(trimmed, "[") && EndsWith(trimmed, "]")) {
                    section = trimmed;
                }
                bool skip = false;
                if (section == "[dependencies]") {
                    int eq = Find(trimmed, "=", 0);
                    if (eq >= 0 && TrimSpaces(Slice(trimmed, 0, eq)) == id) {
                        skip = true;
                        removed = true;
                    }
                }
                if (!skip) {
                    updated = updated + line;
                    if (end < original.Length) { updated = updated + "\n"; }
                }
                at = end + 1;
            }
            if (!removed) {
                System.Console.WriteLine("error: could not find dependency entry for " + id);
                return 1;
            }
            System.IO.File.WriteAllText(projectPath, updated);
            ProjectClosure closure = ProjectClosure.Collect(projectPath);
            if (closure.Error() != "") {
                System.IO.File.WriteAllText(projectPath, original);
                System.Console.WriteLine("error: " + closure.Error());
                return 1;
            }
            string lockText = PackageLock.Render(projectPath, closure);
            if (lockText == "") {
                System.IO.File.WriteAllText(projectPath, original);
                System.Console.WriteLine("error: cannot lock remaining package files");
                return 1;
            }
            System.IO.File.WriteAllText(PathUtils.Join(PathUtils.DirName(projectPath), "hy.lock"), lockText);
            System.Console.WriteLine("removed " + id + " from project");
            return 0;
        }

        private static string TrimSpaces(string value) {
            int begin = 0;
            int end = value.Length;
            while (begin < end && (value[begin] == " " || value[begin] == "\t" || value[begin] == "\r")) {
                begin = begin + 1;
            }
            while (end > begin && (value[end - 1] == " " || value[end - 1] == "\t" || value[end - 1] == "\r")) {
                end = end - 1;
            }
            return Slice(value, begin, end - begin);
        }

        private static int PackageLength(string digits) {
            if (digits.Length == 0 || digits.Length > 8) { return -1; }
            int value = 0;
            int i = 0;
            while (i < digits.Length) {
                int digit = Find("0123456789", digits[i], 0);
                if (digit < 0) { return -1; }
                value = value * 10 + digit;
                i = i + 1;
            }
            return value;
        }

        private static bool StartsWithAt(string value, string prefix, int at) {
            if (at < 0 || at + prefix.Length > value.Length) { return false; }
            int i = 0;
            while (i < prefix.Length) {
                if (value[at + i] != prefix[i]) { return false; }
                i = i + 1;
            }
            return true;
        }

        private static int Find(string value, string needle, int start) {
            int i = start;
            while (i <= value.Length - needle.Length) {
                if (StartsWithAt(value, needle, i)) { return i; }
                i = i + 1;
            }
            return -1;
        }

        private static string Slice(string value, int start, int length) {
            string result = "";
            int i = 0;
            while (i < length) {
                result = result + value[start + i];
                i = i + 1;
            }
            return result;
        }

        private static bool ContainsString(string[] values, string value) {
            int i = 0;
            while (i < values.Length) {
                if (values[i] == value) { return true; }
                i = i + 1;
            }
            return false;
        }

        private static string[] AppendString(string[] values, string value) {
            string[] next = new string[values.Length + 1];
            int i = 0;
            while (i < values.Length) { next[i] = values[i]; i = i + 1; }
            next[values.Length] = value;
            return next;
        }

        private static bool SafePackageFilename(string filename) {
            if (filename == "" || filename == "." || filename == "..") { return false; }
            string letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
            if (Find(letters, filename[0], 0) < 0) { return false; }
            int i = 0;
            while (i < filename.Length) {
                string ch = filename[i];
                if (Find(letters + "._-", ch, 0) < 0) { return false; }
                i = i + 1;
            }
            return true;
        }

        private static string RenderManifest(string name, string type, string source, bool workspace) {
            string text = "format = 2\n";
            text = text + "name = \"" + name + "\"\n";
            text = text + "version = \"0.1.0\"\n";
            text = text + "type = \"" + type + "\"\n";
            if (workspace) {
                text = text + "members = []\n";
            } else if (type == "os" || type == "collection") {
                text = text + "project_references = []\n";
            } else {
                if (type == "efi") {
                    text = text + "output = \"EFI/" + name + ".EFI\"\n";
                } else if (type == "kernel") {
                    text = text + "output = \"EFI/KERNEL.BIN\"\n";
                } else if (type == "driver") {
                    text = text + "output = \"" + name + ".driver\"\n";
                } else if (type == "exec") {
                    text = text + "output = \"" + name + ".exec\"\n";
                } else if (type == "windows") {
                    text = text + "output = \"" + name + ".exe\"\n";
                } else if (type == "macos") {
                    text = text + "output = \"" + name + "\"\n";
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
            if (kind == "kernel") {
                return "public class KernelMain {\n" +
                    "    public static int Run(long bootInfo) {\n" +
                    "        return 0;\n" +
                    "    }\n" +
                    "}\n";
            }
            if (kind == "driver") {
                return "public class DriverMain {\n" +
                    "    public static int Run(long context) {\n" +
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
                if (manifest.Type() == "os" || manifest.Type() == "collection") {
                    return ProcessCollectionProject(path, manifest, "", true, emitIr, null, 0);
                }
                if (manifest.Type() == "exec" || manifest.Type() == "australis") {
                    NativeCompiler execCompiler = new NativeCompiler();
                    NativeCompilerResult execResult = execCompiler.CheckProjectAustralis(path, emitIr);
                    if (!execResult.Success()) {
                        System.Console.Write(execResult.DiagnosticsText());
                        return 1;
                    }
                    System.Console.WriteLine("check ok");
                    if (emitIr) { System.Console.WriteLine(execResult.DiagnosticsText()); }
                    return 0;
                }
                if (manifest.Type() == "native") {
                    NativeCompiler nativeCompiler = new NativeCompiler();
                    NativeCompilerResult nativeResult = nativeCompiler.CheckProjectNativeUser(path, emitIr);
                    if (!nativeResult.Success()) {
                        System.Console.Write(nativeResult.DiagnosticsText());
                        return 1;
                    }
                    System.Console.WriteLine("check ok");
                    if (emitIr) { System.Console.WriteLine(nativeResult.DiagnosticsText()); }
                    return 0;
                }
                if (manifest.Type() == "driver") {
                    NativeCompiler driverCompiler = new NativeCompiler();
                    NativeCompilerResult driverResult = driverCompiler.CheckProjectDriver(path, emitIr);
                    if (!driverResult.Success()) {
                        System.Console.Write(driverResult.DiagnosticsText());
                        return 1;
                    }
                    System.Console.WriteLine("check ok");
                    if (emitIr) { System.Console.WriteLine(driverResult.DiagnosticsText()); }
                    return 0;
                }
                if (manifest.Type() == "windows") {
                    NativeCompiler windowsCompiler = new NativeCompiler();
                    NativeCompilerResult windowsResult = windowsCompiler.CheckProjectWindows(path, emitIr);
                    if (!windowsResult.Success()) {
                        System.Console.Write(windowsResult.DiagnosticsText());
                        return 1;
                    }
                    System.Console.WriteLine("check ok");
                    if (emitIr) { System.Console.WriteLine(windowsResult.DiagnosticsText()); }
                    return 0;
                }
                if (manifest.Type() == "macos") {
                    NativeCompiler macosCompiler = new NativeCompiler();
                    NativeCompilerResult macosResult = macosCompiler.CheckProjectMacOS(path, emitIr);
                    if (!macosResult.Success()) {
                        System.Console.Write(macosResult.DiagnosticsText());
                        return 1;
                    }
                    System.Console.WriteLine("check ok");
                    if (emitIr) { System.Console.WriteLine(macosResult.DiagnosticsText()); }
                    return 0;
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
            bool windows = false;
            bool macos = false;
            string output = "";
            if (args.Length == 4 && args[2] == "-o") {
                output = args[3];
            } else if (args.Length == 6 && args[2] == "--target" && args[3] == "uefi-x64" && args[4] == "-o") {
                uefi = true;
                output = args[5];
            } else if (args.Length == 6 && args[2] == "--target" && args[3] == "windows-x64" && args[4] == "-o") {
                windows = true;
                output = args[5];
            } else if (args.Length == 6 && args[2] == "--target" && args[3] == "macos-x64" && args[4] == "-o") {
                macos = true;
                output = args[5];
            } else {
                System.Console.WriteLine("usage: hy compile <file.hy> -o <output>");
                System.Console.WriteLine("   or: hy compile <file.hy> --target uefi-x64 -o <output>");
                System.Console.WriteLine("   or: hy compile <file.hy> --target windows-x64 -o <output.exe>");
                System.Console.WriteLine("   or: hy compile <file.hy> --target macos-x64 -o <output.exe>");
                return 1;
            }

            NativeCompiler compiler = new NativeCompiler();
            NativeCompilerResult result;
            if (uefi) {
                result = compiler.CompileFileUefi(args[1], output);
            } else if(windows) {
                result = compiler.CompileFileWindows(args[1], output);
            } else if(macos) {
                result = compiler.CompileFileMacOS(args[1], output);
            } else {
                result = compiler.CompileFile(args[1], output);
            }
            if (!result.Success()) {
                System.Console.Write(result.DiagnosticsText());
                return 1;
            }
            System.Console.WriteLine("wrote " + output);
            return 0;
        }

        private static int Build(string[] args) {
            string output = "";
            bool hideProgress = false;
            bool hideSpinner = false;
            bool hideLog = false;
            int option = 2;
            while (option < args.Length) {
                if (args[option] == "-o" || args[option] == "--output") {
                    if (option + 1 >= args.Length || output != "") {
                        System.Console.WriteLine("error: missing or repeated output path");
                        return 1;
                    }
                    output = args[option + 1];
                    option = option + 2;
                } else if (args[option] == "--hide-progress") {
                    hideProgress = true;
                    option = option + 1;
                } else if (args[option] == "--hide-spinner") {
                    hideSpinner = true;
                    option = option + 1;
                } else if (args[option] == "--hide-log") {
                    hideLog = true;
                    option = option + 1;
                } else {
                    System.Console.WriteLine("error: unknown build argument: " + args[option]);
                    return 1;
                }
            }
            if (output == "") {
                System.Console.WriteLine("usage: hy build <project.hyproj> -o <output-file|output-directory> [--hide-progress] [--hide-spinner] [--hide-log]");
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
            BuildProgress progress = new BuildProgress(hideProgress, hideSpinner, hideLog);
            if (manifest.Type() == "os" || manifest.Type() == "collection") {
                return ProcessCollectionProject(projectPath, manifest, output, false, false, progress, 0);
            }
            if (manifest.Type() != "exe" &&
				manifest.Type() != "efi" &&
				manifest.Type() != "kernel" &&
				manifest.Type() != "driver" &&
				manifest.Type() != "australis" &&
				manifest.Type() != "exec" &&
				manifest.Type() != "native" &&
				manifest.Type() != "windows" &&
				manifest.Type() != "macos") {
                System.Console.WriteLine("error: hy build supports exe, windows, efi, kernel, exec, australis, macos, driver, native, and os projects");
                return 1;
            }

            NativeCompiler compiler = new NativeCompiler();
            compiler.SetBuildProgress(progress);
            NativeCompilerResult result;
            if (manifest.Type() == "exe") {
				result = compiler.BuildProject(projectPath, output);
			} else if (manifest.Type() == "kernel") {
				result = compiler.BuildProjectKernel(projectPath, output);
			} else if (manifest.Type() == "driver") {
				result = compiler.BuildProjectDriver(projectPath, output);
			} else if (manifest.Type() == "native") {
                result = compiler.BuildProjectNativeUser(projectPath, output);
			} else if (manifest.Type() == "windows") {
                result = compiler.BuildProjectWindows(projectPath, output);
			} else if (manifest.Type() == "australis" || manifest.Type() == "exec") {
				result = compiler.BuildProjectAustralis(projectPath, output);
			} else if (manifest.Type() == "macos") {
				result = compiler.BuildProjectMacOS(projectPath, output);
			} else {
				result = compiler.BuildProjectUefi(projectPath, output);
			}
            progress.Stop();
            if (!result.Success()) {
                System.Console.Write(result.DiagnosticsText());
                return 1;
            }
            if (!progress.ReportsResult()) { System.Console.WriteLine("wrote " + output); }
            return 0;
        }

        private static int ProcessCollectionProject(string projectPath, HyprojManifest manifest, string outputDirectory, bool check, bool emitIr, BuildProgress progress, int depth) {
            if (depth >= 16) {
                System.Console.WriteLine("error: collection nesting exceeds 16 projects");
                return 1;
            }
            if (manifest.Format() != 2) {
                System.Console.WriteLine("error: unsupported collection project format (expected format = 2)");
                return 1;
            }
            string[] references = manifest.ProjectReferences();
            if (manifest.Sources().Length != 0 || references.Length == 0) {
                System.Console.WriteLine("error: collection projects require project_references and no sources");
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
                if (
					child.Format() != 2 ||
					(
						child.Type() != "exe" &&
						child.Type() != "efi" &&
						child.Type() != "kernel" &&
						child.Type() != "driver" &&
						child.Type() != "exec" &&
						child.Type() != "australis" &&
						child.Type() != "native" &&
						child.Type() != "windows" &&
						child.Type() != "macos" &&
						child.Type() != "collection"
					)
				) {
                    System.Console.WriteLine("error: collection reference must be a format 2 buildable project: " + path);
                    return 1;
                }
                string output = child.Output();
                if (child.Type() != "collection" && !ValidOsOutput(output)) {
                    System.Console.WriteLine("error: project output must be a relative path below the output directory: " + path);
                    return 1;
                }
                if (child.Type() != "collection") { output = PathUtils.Normalize(output); }
                int previous = 0;
                while (previous < i) {
                    if (output != "" && outputs[previous] == output) {
                        System.Console.WriteLine("error: duplicate project output path: " + output);
                        return 1;
                    }
                    previous = previous + 1;
                }
                paths[i] = path;
                outputs[i] = output;
                i = i + 1;
            }

            NativeCompiler compiler = new NativeCompiler();
            if (progress != null) { compiler.SetBuildProgress(progress); }
            int index = 0;
            while (index < paths.Length) {
                string outputPath = PathUtils.Join(outputDirectory, outputs[index]);
                NativeCompilerResult result;
                HyprojManifest childProject = HyprojManifest.Load(paths[index]);
                if (childProject.Type() == "collection") {
                    int nested = ProcessCollectionProject(paths[index], childProject, outputDirectory, check, emitIr, progress, depth + 1);
                    if (nested != 0) { return nested; }
                    index = index + 1;
                    continue;
                }
                if (check) {
                    HyprojManifest checkedChild = HyprojManifest.Load(paths[index]);
                    if (checkedChild.Type() == "exec" || checkedChild.Type() == "australis") {
                        result = compiler.CheckProjectAustralis(paths[index], emitIr);
                    } else if (checkedChild.Type() == "native") {
                        result = compiler.CheckProjectNativeUser(paths[index], emitIr);
                    } else if (checkedChild.Type() == "driver") {
                        result = compiler.CheckProjectDriver(paths[index], emitIr);
                    } else if (checkedChild.Type() == "windows") {
                        result = compiler.CheckProjectWindows(paths[index], emitIr);
                    } else if (checkedChild.Type() == "macos") {
                        result = compiler.CheckProjectMacOS(paths[index], emitIr);
                    } else if (emitIr) { result = compiler.CheckFileEmitIr(paths[index]); }
                    else { result = compiler.CheckFile(paths[index]); }
                } else {
                    HyprojManifest child = HyprojManifest.Load(paths[index]);
                    if (child.Type() == "kernel") { result = compiler.BuildProjectKernel(paths[index], outputPath); }
                    else if (child.Type() == "driver") { result = compiler.BuildProjectDriver(paths[index], outputPath); }
                    else if (child.Type() == "efi") { result = compiler.BuildProjectUefi(paths[index], outputPath); }
                    else if (child.Type() == "native") { result = compiler.BuildProjectNativeUser(paths[index], outputPath); }
                    else if (child.Type() == "windows") { result = compiler.BuildProjectWindows(paths[index], outputPath); }
                    else if (child.Type() == "macos") { result = compiler.BuildProjectMacOS(paths[index], outputPath); }
                    else if (child.Type() == "exec" || child.Type() == "australis") { result = compiler.BuildProjectAustralis(paths[index], outputPath); }
                    else { result = compiler.BuildProject(paths[index], outputPath); }
                }
                if (progress != null) { progress.Stop(); }
                if (!result.Success()) {
                    System.Console.Write(result.DiagnosticsText());
                    return 1;
                }
                if (check) {
                    System.Console.WriteLine("check ok: " + paths[index]);
                    if (emitIr) { System.Console.WriteLine(result.DiagnosticsText()); }
                } else {
                    if (progress == null || !progress.ReportsResult()) { System.Console.WriteLine("wrote " + outputPath); }
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
            System.Console.WriteLine("usage: hy ui <file.hy|project.hyproj> (requires hyui on PATH)");
            System.Console.WriteLine("usage: hy new app|lib|tool|test|workspace|collection|os|efi|kernel|driver|exec|windows|macos <name>");
            System.Console.WriteLine("usage: hy <tokens|parse|check|build> <file.hy|project.hyproj>");
            System.Console.WriteLine("usage: hy check <file.hy> --emit-ir");
            System.Console.WriteLine("usage: hy compile <file.hy> -o <output>");
            System.Console.WriteLine("usage: hy compile <file.hy> --target uefi-x64 -o <output>");
            System.Console.WriteLine("usage: hy compile <file.hy> --target windows-x64 -o <output.exe>");
            System.Console.WriteLine("usage: hy compile <file.hy> --target macos-x64 -o <output>");
            System.Console.WriteLine("usage: hy build <project.hyproj> -o <output-file|output-directory> [--hide-progress] [--hide-spinner] [--hide-log]");
            System.Console.WriteLine("usage: hy stage-compare <project.hyproj> --stage1 <path> --stage2 <path>");
            System.Console.WriteLine("usage: hy package pack <library.hyproj> -o <output.hypkg>");
            System.Console.WriteLine("usage: hy package add <project.hyproj> <source.hypkg>");
            System.Console.WriteLine("usage: hy package remove <project.hyproj> <package-id>");
            System.Console.WriteLine("usage: hy package hash <file>");
            System.Console.WriteLine("usage: hy package lock <project.hyproj>");
            System.Console.WriteLine("installed Linux release commands:");
            System.Console.WriteLine("  hy update-check");
            System.Console.WriteLine("  hy update [--force]");
            System.Console.WriteLine("  hy uninstall [--force]");
            System.Console.WriteLine("  hy remove [--force]");
        }
    }
}
