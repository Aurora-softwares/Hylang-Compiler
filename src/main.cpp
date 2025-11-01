#include "codegen.hpp"
#include "diag.hpp"
#include "lexer.hpp"
#include "linker.hpp"
#include "object_emit.hpp"
#include "parser.hpp"
#include "sema.hpp"
#include "util.hpp"
#include "winrt.hpp"

#include <filesystem>
#include <iostream>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/raw_ostream.h>

namespace hyc {

struct CommandLineOptions {
    std::string input_path;
    std::string output_path;
    std::string emit_ir_path;
    std::string emit_obj_path;
    std::string lld_path;
    bool verbose = false;
};

static void print_usage() {
    std::cerr << "Usage: hydrogenc <input.hy> [options]\n"
              << "Options:\n"
              << "  -o <file>           Output executable path\n"
              << "  --emit-ir <file>    Emit LLVM IR to file\n"
              << "  --emit-obj <file>   Emit object file to path\n"
              << "  --lld <path>        Path to lld-link executable\n"
              << "  -v                  Verbose output\n";
}

static std::optional<CommandLineOptions> parse_arguments(int argc, char** argv) {
    if (argc < 2) {
        print_usage();
        return std::nullopt;
    }

    CommandLineOptions opts;
    opts.input_path = argv[1];

    for (int i = 2; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "-o" && i + 1 < argc) {
            opts.output_path = argv[++i];
        } else if (arg == "--emit-ir" && i + 1 < argc) {
            opts.emit_ir_path = argv[++i];
        } else if (arg == "--emit-obj" && i + 1 < argc) {
            opts.emit_obj_path = argv[++i];
        } else if (arg == "--lld" && i + 1 < argc) {
            opts.lld_path = argv[++i];
        } else if (arg == "-v" || arg == "--verbose") {
            opts.verbose = true;
        } else {
            std::cerr << "Unknown argument: " << arg << "\n";
            print_usage();
            return std::nullopt;
        }
    }

    if (opts.output_path.empty()) {
        std::filesystem::path path(opts.input_path);
        auto stem = path.stem();
        opts.output_path = (path.parent_path() / (stem.string() + ".exe")).string();
    }

    return opts;
}

static bool write_ir(llvm::Module& module, const std::string& path) {
    std::error_code ec;
    llvm::raw_fd_ostream os(path, ec, llvm::sys::fs::OF_Text);
    if (ec) {
        std::cerr << "failed to open IR file: " << ec.message() << "\n";
        return false;
    }
    module.print(os, nullptr);
    return true;
}

} // namespace hyc

int main(int argc, char** argv) {
    auto options = hyc::parse_arguments(argc, argv);
    if (!options) {
        return 1;
    }

    hyc::Diagnostics diags;

    auto source_content = hyc::read_file(options->input_path);
    if (!source_content) {
        std::cerr << "failed to read input file: " << options->input_path << "\n";
        return 1;
    }

    auto buffer = std::make_shared<hyc::SourceBuffer>();
    buffer->filename = options->input_path;
    buffer->lines = hyc::split_lines(*source_content);
    diags.add_buffer(buffer);

    hyc::Lexer lexer(options->input_path, *source_content, diags);
    lexer.lex();
    if (diags.has_errors()) {
        return 1;
    }

    hyc::Parser parser(lexer.tokens(), diags);
    auto program = parser.parse_program();
    if (diags.has_errors()) {
        return 1;
    }

    hyc::SemanticAnalyzer sema(diags);
    if (!sema.analyze(*program)) {
        return 1;
    }

    llvm::LLVMContext context;
    auto module = std::make_unique<llvm::Module>("hydrogen", context);
    module->setSourceFileName(options->input_path);

    hyc::RuntimeSupport runtime(*module);
    hyc::CodeGenerator codegen(context, diags, *module, runtime);
    if (!codegen.emit_program(*program)) {
        return 1;
    }

    if (!options->emit_ir_path.empty()) {
        if (!hyc::write_ir(*module, options->emit_ir_path)) {
            return 1;
        }
    }

    std::filesystem::path object_path;
    bool keep_object = !options->emit_obj_path.empty();
    if (keep_object) {
        object_path = options->emit_obj_path;
    } else {
        std::filesystem::path input_path(options->input_path);
        std::string obj_name = input_path.stem().string() + ".obj";
        object_path = std::filesystem::temp_directory_path() / obj_name;
    }

    if (options->verbose) {
        std::cout << "[hydrogenc] Emitting object: " << object_path.string() << "\n";
    }

    hyc::ObjectEmitter emitter(*module);
    std::string emit_error;
    if (!emitter.emit(object_path.string(), emit_error)) {
        std::cerr << "failed to emit object: " << emit_error << "\n";
        return 1;
    }

    hyc::Linker linker;
    hyc::LinkOptions link_opts;
    link_opts.lld_path = options->lld_path;
    link_opts.object_path = object_path.string();
    link_opts.output_path = options->output_path;
    link_opts.verbose = options->verbose;

    if (options->verbose) {
        std::cout << "[hydrogenc] Linking to executable: " << link_opts.output_path
                  << "\n";
    }

    std::string link_error;
    if (!linker.link(link_opts, link_error)) {
        std::cerr << "linking failed: " << link_error << "\n";
        return 1;
    }

    if (!keep_object) {
        std::error_code ec;
        std::filesystem::remove(object_path, ec);
    }

    if (options->verbose) {
        std::cout << "[hydrogenc] Success: " << link_opts.output_path << "\n";
    }

    return 0;
}
