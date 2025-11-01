#pragma once

#include <cstddef>
#include <string>
#include <vector>

class DiagnosticsEngine {
public:
    void setSource(std::string filename, std::string text);

    void error(std::size_t line, std::size_t column, const std::string &message);

    bool hasErrors() const { return hasErrors_; }

    const std::vector<std::string> &lines() const { return lines_; }
    const std::string &filename() const { return filename_; }

private:
    std::string filename_;
    std::vector<std::string> lines_;
    bool hasErrors_{false};
};

void printDiagnostics(const DiagnosticsEngine &diag);
