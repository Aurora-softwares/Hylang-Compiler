#include "hylang/hylang.hpp"

#include <iostream>
#include <vector>

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "usage: hyrun <file.hy|project.hyproj> [args...]\n";
        return 1;
    }

    hylang::RunOptions options;
    options.input_path = argv[1];
    for (int index = 2; index < argc; ++index) {
        options.args.emplace_back(argv[index]);
    }

    const auto result = hylang::run_target(options);
    if (!result.success) {
        std::cerr << hylang::format_diagnostics(result.diagnostics);
        return 1;
    }

    return 0;
}
