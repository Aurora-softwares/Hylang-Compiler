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
    bool is_warning = false;
};

struct RunOptions {
    std::filesystem::path input_path;
    std::vector<std::string> args;
};

struct RunResult {
    bool success = false;
    std::vector<Diagnostic> diagnostics;
    int exit_code = 0;
};

struct BuildOptions {
    std::filesystem::path input_path;
    std::optional<std::string> forced_target;
    std::optional<std::filesystem::path> output_path;
    bool debug = false;
};

struct BuildResult {
    bool success = false;
    std::vector<Diagnostic> diagnostics;
    std::filesystem::path output_path;
    std::filesystem::path source_map_path;
    bool cache_hit = false;
};

struct CheckOptions {
    std::filesystem::path input_path;
};

struct CheckResult {
    bool success = false;
    std::vector<Diagnostic> diagnostics;
};

struct TestOptions {
    std::filesystem::path input_path;
};

struct TestRun {
    std::filesystem::path project_path;
    int exit_code = 0;
};

struct TestResult {
    bool success = false;
    std::vector<Diagnostic> diagnostics;
    std::vector<TestRun> runs;
};

RunResult run_target(const RunOptions& options);
BuildResult build_target(const BuildOptions& options);
CheckResult check_target(const CheckOptions& options);
TestResult test_target(const TestOptions& options);
std::string format_diagnostics(const std::vector<Diagnostic>& diagnostics);

}  // namespace hylang
