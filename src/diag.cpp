#include "diag.hpp"

#include <algorithm>
#include <iostream>

namespace hyc {

void Diagnostics::error(const SourceLocation &loc, const std::string &lineText, unsigned start, unsigned length, std::string message) {
    Diagnostic diag;
    diag.level = Diagnostic::Level::Error;
    diag.location = loc;
    diag.message = std::move(message);
    diag.lineText = lineText;
    diag.underlineStart = start;
    diag.underlineLength = length == 0 ? 1 : length;
    m_hasErrors = true;
    m_messages.push_back(std::move(diag));
}

static const char *levelToString(Diagnostic::Level level) {
    switch (level) {
    case Diagnostic::Level::Error:
        return "error";
    case Diagnostic::Level::Warning:
        return "warning";
    case Diagnostic::Level::Note:
        return "note";
    }
    return "unknown";
}

void Diagnostics::printToStderr() const {
    for (const auto &diag : m_messages) {
        std::cerr << diag.location.file << ':' << diag.location.line << ':' << diag.location.column << ": "
                  << levelToString(diag.level) << ": " << diag.message << '\n';
        if (!diag.lineText.empty()) {
            std::cerr << diag.lineText << '\n';
            unsigned caretPos = diag.underlineStart;
            unsigned underlineLen = diag.underlineLength;
            for (unsigned i = 0; i < caretPos; ++i) {
                std::cerr << ' ';
            }
            std::cerr << '^';
            for (unsigned i = 1; i < underlineLen; ++i) {
                std::cerr << '~';
            }
            std::cerr << '\n';
        }
    }
}

} // namespace hyc
