#include "util.hpp"

#include <algorithm>
#include <cctype>
#include <fstream>

#include <llvm/Support/FileSystem.h>

namespace hydrogenc {

std::optional<std::string> read_file(const std::filesystem::path& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        return std::nullopt;
    }
    std::string contents;
    file.seekg(0, std::ios::end);
    contents.resize(static_cast<std::size_t>(file.tellg()));
    file.seekg(0, std::ios::beg);
    file.read(contents.data(), static_cast<std::streamsize>(contents.size()));
    return contents;
}

bool write_file(const std::filesystem::path& path, std::string_view data, std::string& error) {
    std::error_code ec;
    llvm::raw_fd_ostream os(path.string(), ec, llvm::sys::fs::OF_None);
    if (ec) {
        error = ec.message();
        return false;
    }
    os << data;
    return true;
}

std::vector<std::string> split_lines(std::string_view text) {
    std::vector<std::string> lines;
    std::size_t start = 0;
    while (start < text.size()) {
        auto end = text.find('\n', start);
        if (end == std::string_view::npos) {
            lines.emplace_back(text.substr(start));
            break;
        }
        lines.emplace_back(text.substr(start, end - start));
        start = end + 1;
    }
    if (text.empty() || text.back() == '\n') {
        lines.emplace_back("");
    }
    return lines;
}

std::string to_lower_copy(std::string_view text) {
    std::string result(text);
    std::transform(result.begin(), result.end(), result.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return result;
}

std::filesystem::path change_extension(const std::filesystem::path& path, const std::string& ext) {
    auto result = path;
    result.replace_extension(ext);
    return result;
}

std::filesystem::path make_temporary_obj(const std::string& prefix, std::string& error) {
    llvm::SmallString<128> temp_path;
    std::error_code ec = llvm::sys::fs::createTemporaryFile(prefix, "obj", temp_path);
    if (ec) {
        error = ec.message();
        return {};
    }
    return std::filesystem::path(temp_path.str().str());
}

} // namespace hydrogenc
