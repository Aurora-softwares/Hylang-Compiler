#include "util.hpp"

#include <algorithm>
#include <cctype>
#include <fstream>
#include <iterator>
#include <sstream>

namespace hyc {

std::string to_lower_copy(std::string_view text) {
    std::string result(text);
    std::transform(result.begin(), result.end(), result.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return result;
}

std::vector<std::string> split_lines(const std::string& content) {
    std::vector<std::string> lines;
    std::istringstream ss(content);
    std::string line;
    while (std::getline(ss, line)) {
        lines.push_back(line);
    }
    if (!content.empty() && (content.back() == '\n' || content.back() == '\r')) {
        if (lines.empty() || content.back() == '\n') {
            // Ensure trailing newline adds an empty line to keep indices aligned.
            lines.push_back("");
        }
    }
    if (lines.empty()) {
        lines.emplace_back("");
    }
    return lines;
}

std::optional<std::string> read_file(const std::string& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        return std::nullopt;
    }
    std::ostringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

} // namespace hyc
