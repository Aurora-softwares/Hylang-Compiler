#pragma once

#include "tokens.hpp"

#include <string>
#include <string_view>
#include <vector>

namespace hydrogenc {

enum class DiagnosticLevel {
    Note,
    Warning,
    Error,
};

struct Diagnostic {
    DiagnosticLevel level = DiagnosticLevel::Error;
    SourceLocation location;
    std::string message;
    std::size_t highlight_length = 1;
};

class DiagnosticEngine {
public:
    void set_source(std::string filename, std::vector<std::string> lines);

    void report(Diagnostic diag);
    bool has_error() const { return has_error_; }
    void flush_to_stderr() const;

private:
    std::string filename_;
    std::vector<std::string> lines_;
    std::vector<Diagnostic> diagnostics_;
    bool has_error_ = false;
};

} // namespace hydrogenc
