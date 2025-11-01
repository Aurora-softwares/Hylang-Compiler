#pragma once

#include <algorithm>
#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

struct SourceLocation {
    std::size_t line{0};
    std::size_t column{0};
};

std::vector<std::string> splitLines(const std::string &text);
std::string toLowerCopy(std::string_view text);

class ScopedIndent {
public:
    explicit ScopedIndent(std::string &indent) : indent_(indent) { indent_ += "  "; }
    ~ScopedIndent() { indent_.erase(indent_.size() - 2); }
private:
    std::string &indent_;
};
