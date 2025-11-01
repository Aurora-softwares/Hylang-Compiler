#include "diag.hpp"

#include <algorithm>
#include <cstddef>
#include <iomanip>
#include <iostream>
#include <sstream>

namespace hyc {

namespace {
std::string indent(std::size_t count) {
    return std::string(count, ' ');
}
} // namespace

Diagnostics::Diagnostics(Sink sink) : sink_(std::move(sink)) {}

Diagnostics::Sink Diagnostics::default_sink() {
    return [](const std::string& msg) { std::cerr << msg << "\n"; };
}

void Diagnostics::add_buffer(std::shared_ptr<SourceBuffer> buffer) {
    buffers_.push_back(std::move(buffer));
}

void Diagnostics::error(const SourceLocation& loc, const std::string& message,
                        std::size_t highlight_length) {
    has_errors_ = true;
    sink_(format_message(loc, message, highlight_length));
}

std::string Diagnostics::format_message(const SourceLocation& loc,
                                        const std::string& message,
                                        std::size_t highlight_length) const {
    std::ostringstream os;
    os << loc.file << ':' << loc.line << ':' << loc.column << ": error: "
       << message << '\n';

    auto it = std::find_if(buffers_.begin(), buffers_.end(),
                           [&](const std::shared_ptr<SourceBuffer>& buf) {
                               return buf->filename == loc.file;
                           });
    if (it != buffers_.end()) {
        const auto& lines = (*it)->lines;
        if (loc.line >= 1 && loc.line <= lines.size()) {
            const std::string& line = lines[loc.line - 1];
            os << line << '\n';
            std::size_t caret_pos = std::min(loc.column - 1, line.size());
            os << indent(caret_pos) << '^';
            if (highlight_length > 1) {
                os << std::string(highlight_length - 1, '~');
            }
            os << '\n';
        }
    }

    return os.str();
}

} // namespace hyc
