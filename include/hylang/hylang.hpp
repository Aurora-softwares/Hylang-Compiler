#pragma once

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace hylang {

struct Diagnostic {
    std::filesystem::path file;
    int line = 1;
    int column = 1;
    std::string message;
};

struct RunOptions {
    std::filesystem::path input_path;
    std::vector<std::string> args;
};

struct RunResult {
    bool success = false;
    std::vector<Diagnostic> diagnostics;
};

struct BuildOptions {
    std::filesystem::path input_path;
    std::optional<std::string> forced_target;
    std::optional<std::filesystem::path> output_path;
};

struct BuildResult {
    bool success = false;
    std::vector<Diagnostic> diagnostics;
    std::filesystem::path output_path;
};

RunResult run_target(const RunOptions& options);
BuildResult build_target(const BuildOptions& options);
std::string format_diagnostics(const std::vector<Diagnostic>& diagnostics);

}  // namespace hylang
