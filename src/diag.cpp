#include "diag.hpp"

#include <algorithm>
#include <iostream>
#include <sstream>

namespace hydrogenc {

namespace {
std::string level_to_string(DiagnosticLevel level) {
    switch (level) {
    case DiagnosticLevel::Note:
        return "note";
    case DiagnosticLevel::Warning:
        return "warning";
    case DiagnosticLevel::Error:
    default:
        return "error";
    }
}
} // namespace

void DiagnosticEngine::set_source(std::string filename, std::vector<std::string> lines) {
    filename_ = std::move(filename);
    lines_ = std::move(lines);
    diagnostics_.clear();
    has_error_ = false;
}

void DiagnosticEngine::report(Diagnostic diag) {
    if (diag.level == DiagnosticLevel::Error) {
        has_error_ = true;
    }
    diagnostics_.push_back(std::move(diag));
}

void DiagnosticEngine::flush_to_stderr() const {
    for (const auto& diag : diagnostics_) {
        std::ostringstream oss;
        oss << filename_ << ':' << diag.location.line << ':' << diag.location.column << ": "
            << level_to_string(diag.level) << ": " << diag.message << '\n';

        if (diag.location.line > 0 && diag.location.line <= lines_.size()) {
            const auto& line = lines_[diag.location.line - 1];
            oss << line << '\n';
            std::size_t caret_pos = std::min(diag.location.column, line.size() + 1);
            for (std::size_t i = 1; i < caret_pos; ++i) {
                oss << ' ';
            }
            std::size_t length = std::max<std::size_t>(1, diag.highlight_length);
            oss << '^';
            for (std::size_t i = 1; i < length; ++i) {
                oss << '~';
            }
            oss << '\n';
        }

        std::cerr << oss.str();
    }
}

} // namespace hydrogenc
