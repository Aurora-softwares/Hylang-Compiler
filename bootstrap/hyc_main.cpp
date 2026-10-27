#include "hylang/hylang.hpp"
#include "build_display.hpp"

#include <iostream>
#include <optional>
#include <string>

int main(int argc, char** argv) {
    if (argc < 3 || std::string(argv[1]) != "build") {
        std::cerr << "usage: hyc build <file.hy|project.hyproj> [--target exe|lib] [-o output] [--hide-progress] [--hide-spinner] [--hide-log]\n";
        return 1;
    }

    hylang::BuildOptions options;
    options.input_path = argv[2];
    bool hide_progress = false;
    bool hide_spinner = false;
    bool hide_log = false;

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

        if (argument == "--hide-progress") { hide_progress = true; continue; }
        if (argument == "--hide-spinner") { hide_spinner = true; continue; }
        if (argument == "--hide-log") { hide_log = true; continue; }

        std::cerr << "unknown argument: " << argument << "\n";
        return 1;
    }

    BuildDisplay display(hide_progress, hide_spinner, hide_log);
    options.progress = [&](std::size_t done, std::size_t total, const std::string& message) {
        display.update(done, total, message);
    };
    options.action_progress = [&](std::size_t percent) { display.action_progress(percent); };
    display.begin(options.input_path.string());
    const auto result = hylang::build_target(options);
    display.finish();
    if (!result.success) {
        std::cerr << hylang::format_diagnostics(result.diagnostics);
        return 1;
    }

    std::cout << result.output_path.string() << "\n";
    return 0;
}
