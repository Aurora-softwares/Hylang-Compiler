#include "util.hpp"

#include <cctype>

std::vector<std::string> splitLines(const std::string &text) {
    std::vector<std::string> lines;
    std::size_t start = 0;
    for (std::size_t i = 0; i < text.size(); ++i) {
        if (text[i] == '\n') {
            lines.emplace_back(text.substr(start, i - start));
            start = i + 1;
        }
    }
    if (start <= text.size()) {
        lines.emplace_back(text.substr(start));
    }
    return lines;
}

std::string toLowerCopy(std::string_view text) {
    std::string result{text};
    std::transform(result.begin(), result.end(), result.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return result;
}
