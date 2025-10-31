#include "codegen.hpp"
#include "diag.hpp"
#include "lexer.hpp"
#include "linker.hpp"
#include "object_emit.hpp"
#include "parser.hpp"
#include "sema.hpp"
#include "util.hpp"

#include <filesystem>
#include <iostream>
#include <optional>
#include <string>
#include <system_error>
#include <vector>
#include <utility>

#include <llvm/Support/FileSystem.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Support/raw_ostream.h>

namespace hydrogenc {
namespace {

struct Options {
    std::filesystem::path input;
    std::filesystem::path output;
    std::optional<std::filesystem::path> emit_ir;
    std::optional<std::filesystem::path> emit_obj;
    bool verbose = false;
};

void print_usage() {
    std::cerr << "Usage: hydrogenc <input.hy> [options]\n"
              << "Options:\n"
              << "  -o <file>         Set output executable path\n"
              << "  --emit-ir <file>  Write LLVM IR to file\n"
              << "  --emit-obj <file> Keep intermediate object file\n"
              << "  -v                Verbose mode\n";
}

std::optional<Options> parse_options(int argc, char** argv) {
    Options opts;
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "-o") {
            if (i + 1 >= argc) {
                std::cerr << "error: -o requires a value\n";
                return std::nullopt;
            }
            opts.output = argv[++i];
        } else if (arg == "--emit-ir") {
            if (i + 1 >= argc) {
                std::cerr << "error: --emit-ir requires a value\n";
                return std::nullopt;
            }
            opts.emit_ir = argv[++i];
        } else if (arg == "--emit-obj") {
            if (i + 1 >= argc) {
                std::cerr << "error: --emit-obj requires a value\n";
                return std::nullopt;
            }
            opts.emit_obj = argv[++i];
        } else if (arg == "-v") {
            opts.verbose = true;
        } else if (arg == "-h" || arg == "--help") {
            print_usage();
            return std::nullopt;
        } else if (!arg.empty() && arg[0] == '-') {
            std::cerr << "error: unknown option '" << arg << "'\n";
            return std::nullopt;
        } else {
            if (!opts.input.empty()) {
                std::cerr << "error: multiple input files specified\n";
                return std::nullopt;
            }
            opts.input = arg;
        }
    }

    if (opts.input.empty()) {
        print_usage();
        return std::nullopt;
    }

    if (opts.output.empty()) {
        opts.output = change_extension(opts.input, ".exe");
    }

    return opts;
}

} // namespace
} // namespace hydrogenc

int main(int argc, char** argv) {
    llvm::InitializeAllTargetInfos();
    llvm::InitializeAllTargets();
    llvm::InitializeAllTargetMCs();
    llvm::InitializeAllAsmPrinters();
    llvm::InitializeAllAsmParsers();

    auto opts_opt = hydrogenc::parse_options(argc, argv);
    if (!opts_opt) {
        return 1;
    }
    auto opts = *opts_opt;

    auto source_opt = hydrogenc::read_file(opts.input);
    if (!source_opt) {
        std::cerr << "error: unable to read file '" << opts.input << "'\n";
        return 1;
    }
    auto source = *source_opt;

    hydrogenc::DiagnosticEngine diag;
    diag.set_source(opts.input.string(), hydrogenc::split_lines(source));

    hydrogenc::Lexer lexer(std::move(source), diag);
    auto tokens = lexer.lex();
    if (diag.has_error()) {
        diag.flush_to_stderr();
        return 1;
    }

    hydrogenc::Parser parser(tokens, diag);
    std::unique_ptr<hydrogenc::Program> program;
    try {
        program = parser.parse_program();
    } catch (const std::runtime_error&) {
        diag.flush_to_stderr();
        return 1;
    }

    if (!program || diag.has_error()) {
        diag.flush_to_stderr();
        return 1;
    }

    hydrogenc::Sema sema(diag);
    if (!sema.analyze(*program)) {
        diag.flush_to_stderr();
        return 1;
    }

    if (opts.verbose) {
        std::cerr << "[hydrogenc] generating LLVM IR\n";
    }
    hydrogenc::CodeGenerator codegen;
    auto module = codegen.generate(*program, opts.input.filename().string());

    if (opts.emit_ir) {
        std::error_code ec;
        llvm::raw_fd_ostream ir_stream(opts.emit_ir->string(), ec, llvm::sys::fs::OF_None);
        if (ec) {
            std::cerr << "error: unable to write IR file: " << ec.message() << "\n";
            return 1;
        }
        module->print(ir_stream, nullptr);
    }

    std::filesystem::path object_path;
    bool keep_object = false;
    if (opts.emit_obj) {
        object_path = *opts.emit_obj;
        keep_object = true;
    } else {
        std::string temp_error;
        object_path = hydrogenc::make_temporary_obj("hydrogen", temp_error);
        if (object_path.empty()) {
            std::cerr << "error: unable to create temporary object file: " << temp_error << "\n";
            return 1;
        }
    }

    if (opts.verbose) {
        std::cerr << "[hydrogenc] emitting object: " << object_path << "\n";
    }

    std::string obj_error;
    if (!hydrogenc::emit_object(*module, object_path, obj_error)) {
        std::cerr << "error: failed to emit object: " << obj_error << "\n";
        if (!keep_object && !object_path.empty()) {
            std::error_code ec;
            std::filesystem::remove(object_path, ec);
        }
        return 1;
    }

    if (opts.verbose) {
        std::cerr << "[hydrogenc] linking executable: " << opts.output << "\n";
    }

    std::string link_error;
    if (!hydrogenc::link_executable(object_path, opts.output, link_error, opts.verbose)) {
        std::cerr << "error: linking failed: " << link_error << "\n";
        if (!keep_object) {
            std::error_code ec;
            std::filesystem::remove(object_path, ec);
        }
        return 1;
    }

    if (!keep_object) {
        std::error_code ec;
        std::filesystem::remove(object_path, ec);
    }

    if (opts.verbose) {
        std::cerr << "[hydrogenc] success -> " << opts.output << "\n";
    }

    return 0;
}
