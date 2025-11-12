#pragma once

#include <iostream>
#include <string>

namespace hy {

struct SourceLocation {
    std::size_t line{1};
    std::size_t column{1};
};

class DiagnosticEngine {
public:
    void error(SourceLocation loc, const std::string &message);
    void error(const std::string &message);
    bool hasError() const { return hadError_; }

private:
    bool hadError_{false};
};

std::string formatLocation(SourceLocation loc);

} // namespace hy
