#include "CLI.h"

#include <fstream>
#include <sstream>

#include <llvm/Support/FileSystem.h>
#include <llvm/Support/raw_ostream.h>

#include "Lexer.h"
#include "Parser.h"

namespace hy {

CLI::CLI(DiagnosticEngine &diag) : diag_(diag) {}

int CLI::run(int argc, char **argv) {
    if (argc < 2) {
        llvm::errs() << "usage: hyc <command> [file]" << '\n';
        llvm::errs() << "commands: ir, build, version" << '\n';
        return 1;
    }

    std::string command = argv[1];
    if (command == "version") {
        llvm::outs() << "hyc " << HY_VERSION << "\n";
        return 0;
    }

    if (argc < 3) {
        diag_.error("expected input file path");
        return 1;
    }

    std::string path = argv[2];

    if (command == "ir") {
        return handleIR(path);
    }
    if (command == "build") {
        return handleBuild(path);
    }

    diag_.error("unknown command '" + command + "'");
    return 1;
}

std::string CLI::loadFile(const std::string &path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        diag_.error("failed to open file '" + path + "'");
        return {};
    }
    std::ostringstream ss;
    ss << file.rdbuf();
    return ss.str();
}

int CLI::handleIR(const std::string &path) {
    std::string source = loadFile(path);
    if (source.empty() && diag_.hasError()) {
        return 1;
    }

    Lexer lexer(source, diag_);
    auto tokens = lexer.tokenize();
    if (diag_.hasError()) {
        return 1;
    }

    Parser parser(tokens, diag_);
    auto moduleAst = parser.parse();
    if (!moduleAst || diag_.hasError()) {
        return 1;
    }

    CodeGenerator codegen(diag_);
    auto module = codegen.codegen(*moduleAst, "hydrogen");
    if (!module || diag_.hasError()) {
        return 1;
    }

    codegen.printIR(*module, llvm::outs());
    return 0;
}

int CLI::handleBuild(const std::string &path) {
    std::string source = loadFile(path);
    if (source.empty() && diag_.hasError()) {
        return 1;
    }

    Lexer lexer(source, diag_);
    auto tokens = lexer.tokenize();
    if (diag_.hasError()) {
        return 1;
    }

    Parser parser(tokens, diag_);
    auto moduleAst = parser.parse();
    if (!moduleAst || diag_.hasError()) {
        return 1;
    }

    CodeGenerator codegen(diag_);
    auto module = codegen.codegen(*moduleAst, "hydrogen");
    if (!module || diag_.hasError()) {
        return 1;
    }

#ifdef _WIN32
    std::string output = "a.exe";
#else
    std::string output = "a.out";
#endif
    std::string objectPath = output + ".o";

    if (!codegen.emitObject(*module, objectPath)) {
        llvm::sys::fs::remove(objectPath);
        return 1;
    }
    if (!codegen.linkExecutable(objectPath, output)) {
        llvm::sys::fs::remove(objectPath);
        return 1;
    }

    llvm::sys::fs::remove(objectPath);
    llvm::outs() << "wrote executable to " << output << "\n";
    return 0;
}

} // namespace hy
