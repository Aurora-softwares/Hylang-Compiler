#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <optional>
#include <string>
#include <vector>

#include <llvm/Support/FileSystem.h>
#include <llvm/Support/raw_ostream.h>

#include "codegen.hpp"
#include "diag.hpp"
#include "lexer.hpp"
#include "linker.hpp"
#include "object_emit.hpp"
#include "parser.hpp"
#include "sema.hpp"

struct Options {
    std::string input;
    std::optional<std::string> output;
    std::optional<std::string> emitIR;
    std::optional<std::string> emitObj;
    bool verbose{false};
};

namespace {

void printUsage() {
    std::cerr << "Usage: hydrogenc <input.hy> [-o output.exe] [--emit-ir file.ll] [--emit-obj file.obj] [-v]\n";
}

bool parseArgs(int argc, char **argv, Options &options) {
    if (argc < 2) {
        printUsage();
        return false;
    }
    options.input = argv[1];
    for (int i = 2; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "-o" && i + 1 < argc) {
            options.output = argv[++i];
        } else if (arg == "--emit-ir" && i + 1 < argc) {
            options.emitIR = argv[++i];
        } else if (arg == "--emit-obj" && i + 1 < argc) {
            options.emitObj = argv[++i];
        } else if (arg == "-v" || arg == "--verbose") {
            options.verbose = true;
        } else {
            std::cerr << "Unknown argument: " << arg << "\n";
            return false;
        }
    }
    return true;
}

std::optional<std::string> readFile(const std::filesystem::path &path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        return std::nullopt;
    }
    std::string contents((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    return contents;
}

std::vector<std::string> parseLibEnv() {
    std::vector<std::string> paths;
#ifdef _WIN32
    if (const char *libEnv = std::getenv("LIB")) {
        std::string value = libEnv;
        std::string current;
        for (char ch : value) {
            if (ch == ';') {
                if (!current.empty()) {
                    paths.push_back(current);
                    current.clear();
                }
            } else {
                current.push_back(ch);
            }
        }
        if (!current.empty()) {
            paths.push_back(current);
        }
    }
#endif
    return paths;
}

} // namespace

int main(int argc, char **argv) {
    Options options;
    if (!parseArgs(argc, argv, options)) {
        return 1;
    }

    std::filesystem::path inputPath = options.input;
    if (!std::filesystem::exists(inputPath)) {
        std::cerr << "Input file not found: " << inputPath << "\n";
        return 1;
    }

    auto sourceOpt = readFile(inputPath);
    if (!sourceOpt) {
        std::cerr << "Failed to read input file: " << inputPath << "\n";
        return 1;
    }
    std::string source = *sourceOpt;

    DiagnosticsEngine diag;
    diag.setSource(inputPath.string(), source);

    Lexer lexer(inputPath.string(), source, diag);
    Parser parser(lexer, diag);
    auto program = parser.parseProgram();
    if (diag.hasErrors()) {
        printDiagnostics(diag);
        return 1;
    }

    Sema sema(diag);
    if (!sema.analyze(*program)) {
        printDiagnostics(diag);
        return 1;
    }

    CodeGenerator codegen(diag, sema, inputPath.filename().string());
    if (!codegen.generate(*program)) {
        printDiagnostics(diag);
        return 1;
    }

    if (options.emitIR) {
        std::error_code ec;
        llvm::raw_fd_ostream irOut(*options.emitIR, ec, llvm::sys::fs::OF_Text);
        if (ec) {
            std::cerr << "Failed to open IR output: " << ec.message() << "\n";
            return 1;
        }
        codegen.module().print(irOut, nullptr);
    }

    std::filesystem::path exePath;
    if (options.output) {
        exePath = *options.output;
    } else {
        exePath = inputPath;
        exePath.replace_extension(".exe");
    }

    std::filesystem::path objPath;
    bool keepObject = false;
    if (options.emitObj) {
        objPath = *options.emitObj;
        keepObject = true;
    } else {
        objPath = exePath;
        objPath.replace_extension(".obj");
    }

    std::string emitError;
    if (!emitObjectFile(codegen.module(), objPath.string(), emitError)) {
        std::cerr << "Failed to emit object file: " << emitError << "\n";
        return 1;
    }

    auto libPaths = parseLibEnv();
    std::string linkError;
    if (!linkExecutable(objPath.string(), exePath.string(), linkError, options.verbose, libPaths)) {
        std::cerr << "Link failed: " << linkError << "\n";
        return 1;
    }

    if (!keepObject) {
        std::error_code ec;
        std::filesystem::remove(objPath, ec);
    }

    if (options.verbose) {
        std::cout << "Wrote " << exePath << "\n";
    }

    return 0;
}
