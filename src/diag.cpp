#include "diag.hpp"

#include <iostream>

#include "util.hpp"

void DiagnosticsEngine::setSource(std::string filename, std::string text) {
    filename_ = std::move(filename);
    lines_ = splitLines(text);
}

void DiagnosticsEngine::error(std::size_t line, std::size_t column, const std::string &message) {
    hasErrors_ = true;
    if (line == 0 || line > lines_.size()) {
        std::cerr << filename_ << ":" << line << ":" << column << ": error: " << message << "\n";
        return;
    }
    const auto &lineText = lines_[line - 1];
    std::cerr << filename_ << ":" << line << ":" << column << ": error: " << message << "\n";
    std::cerr << lineText << "\n";
    std::cerr << std::string(column > 1 ? column - 1 : 0, ' ');
    std::size_t underline = column > 0 && column <= lineText.size() ? 1 : 0;
    if (underline == 0 && column == lineText.size() + 1) {
        underline = 1;
    }
    std::cerr << std::string(underline ? underline : 1, '^') << "\n";
}

void printDiagnostics(const DiagnosticsEngine &diag) {
    if (!diag.hasErrors()) {
        return;
    }
    (void)diag; // errors already printed eagerly
}
