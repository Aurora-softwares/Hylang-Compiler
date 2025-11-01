#include "codegen.hpp"
#include "diag.hpp"
#include "lexer.hpp"
#include "linker.hpp"
#include "object_emit.hpp"
#include "parser.hpp"
#include "sema.hpp"
#include "util.hpp"

#include <llvm/Support/FileSystem.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Support/raw_ostream.h>

#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

namespace hyc {

static void printUsage() {
    std::cout << "Usage: hydrogenc <input.hy> [options]\n"
              << "Options:\n"
              << "  -o <file>        Output executable path (default: input basename + .exe)\n"
              << "  --emit-ir <file> Write LLVM IR to file\n"
              << "  --emit-obj <file>Keep generated object file\n"
              << "  --lld <path>     Path to lld-link executable\n"
              << "  -v, --verbose    Verbose build steps\n"
              << "  -h, --help       Show this help\n";
}

} // namespace hyc

int main(int argc, char **argv) {
    using namespace hyc;

    std::string inputPath;
    std::string outputPath;
    std::string emitIrPath;
    std::string emitObjPath;
    std::string lldPath;
    bool verbose = false;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "-h" || arg == "--help") {
            printUsage();
            return 0;
        } else if ((arg == "-o" || arg == "--output") && i + 1 < argc) {
            outputPath = argv[++i];
        } else if (arg == "--emit-ir" && i + 1 < argc) {
            emitIrPath = argv[++i];
        } else if (arg == "--emit-obj" && i + 1 < argc) {
            emitObjPath = argv[++i];
        } else if (arg == "--lld" && i + 1 < argc) {
            lldPath = argv[++i];
        } else if (arg == "-v" || arg == "--verbose") {
            verbose = true;
        } else if (!arg.empty() && arg[0] == '-') {
            std::cerr << "Unknown option: " << arg << "\n";
            printUsage();
            return 1;
        } else if (inputPath.empty()) {
            inputPath = arg;
        } else {
            std::cerr << "Unexpected argument: " << arg << "\n";
            printUsage();
            return 1;
        }
    }

    if (inputPath.empty()) {
        printUsage();
        return 1;
    }

    if (outputPath.empty()) {
        outputPath = replaceExtension(inputPath, ".exe");
    }

    std::string source;
    std::string error;
    if (!readFile(inputPath, source, error)) {
        std::cerr << error << "\n";
        return 1;
    }

    Diagnostics diagnostics;
    Lexer lexer(source, inputPath, diagnostics);
    auto tokens = lexer.lex();

    Parser parser(tokens, source, diagnostics);
    auto program = parser.parseProgram();

    Sema sema(diagnostics, source);
    sema.analyze(program);

    if (diagnostics.hasErrors()) {
        diagnostics.printToStderr();
        return 1;
    }

    llvm::InitializeAllTargetInfos();
    llvm::InitializeAllTargets();
    llvm::InitializeAllTargetMCs();
    llvm::InitializeAllAsmParsers();
    llvm::InitializeAllAsmPrinters();

    CodeGenerator codegen(sema);
    auto module = codegen.generate(program, std::filesystem::path(inputPath).stem().string());

    if (!emitIrPath.empty()) {
        std::error_code ec;
        llvm::raw_fd_ostream irOut(emitIrPath, ec, llvm::sys::fs::OF_Text);
        if (ec) {
            std::cerr << "failed to open IR output: " << ec.message() << "\n";
            return 1;
        }
        module->print(irOut, nullptr);
    }

    std::string objectPath = emitObjPath;
    std::filesystem::path tempObjPath;
    if (objectPath.empty()) {
        auto tempDir = std::filesystem::temp_directory_path();
        auto pattern = std::filesystem::path(inputPath).stem().string() + "-%%%%%%%.obj";
        tempObjPath = std::filesystem::unique_path(tempDir / pattern);
        objectPath = tempObjPath.string();
    }

    if (verbose) {
        std::cout << "[codegen] Emitting object: " << objectPath << "\n";
    }

    if (!emitObjectFile(*module, objectPath, error)) {
        std::cerr << "object emission failed: " << error << "\n";
        return 1;
    }

    std::vector<std::string> libraries;
    if (!linkExecutable(objectPath, outputPath, libraries, lldPath, verbose, error)) {
        std::cerr << "linking failed: " << error << "\n";
        return 1;
    }

    if (verbose) {
        std::cout << "[link] Produced " << outputPath << "\n";
    }

    if (emitObjPath.empty() && !tempObjPath.empty()) {
        std::error_code removeEc;
        std::filesystem::remove(tempObjPath, removeEc);
    }

    return 0;
}
