#include "hylang/hylang.hpp"

#include <iostream>
#include <optional>
#include <string>

int main(int argc, char** argv) {
    if (argc < 3 || std::string(argv[1]) != "build") {
        std::cerr << "usage: hyc build <file.hy|project.hyproj> [--target exe|lib] [-o output]\n";
        return 1;
    }

    hylang::BuildOptions options;
    options.input_path = argv[2];

    for (int index = 3; index < argc; ++index) {
        const std::string argument = argv[index];
        if (argument == "--target") {
            if (index + 1 >= argc) {
                std::cerr << "missing value after --target\n";
                return 1;
            }
            options.forced_target = std::string(argv[++index]);
            continue;
        }

        if (argument == "-o" || argument == "--output") {
            if (index + 1 >= argc) {
                std::cerr << "missing value after " << argument << "\n";
                return 1;
            }
            options.output_path = std::string(argv[++index]);
            continue;
        }

        std::cerr << "unknown argument: " << argument << "\n";
        return 1;
    }

    const auto result = hylang::build_target(options);
    if (!result.success) {
        std::cerr << hylang::format_diagnostics(result.diagnostics);
        return 1;
    }

    std::cout << result.output_path.string() << "\n";
    return 0;
}
