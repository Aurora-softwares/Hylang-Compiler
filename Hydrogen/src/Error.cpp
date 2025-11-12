#include "Error.h"

#include <iomanip>

namespace hy {

void DiagnosticEngine::error(SourceLocation loc, const std::string &message) {
    hadError_ = true;
    std::cerr << "error: " << formatLocation(loc) << ": " << message << "\n";
}

void DiagnosticEngine::error(const std::string &message) {
    hadError_ = true;
    std::cerr << "error: " << message << "\n";
}

std::string formatLocation(SourceLocation loc) {
    return "line " + std::to_string(loc.line) + ", column " + std::to_string(loc.column);
}

} // namespace hy
