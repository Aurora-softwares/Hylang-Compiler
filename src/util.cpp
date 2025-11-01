#include "util.hpp"

#include <filesystem>
#include <fstream>
#include <sstream>

namespace hyc {

bool readFile(const std::string &path, std::string &out, std::string &error) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        error = "failed to open file '" + path + "'";
        return false;
    }
    std::ostringstream ss;
    ss << in.rdbuf();
    out = ss.str();
    return true;
}

bool writeFile(const std::string &path, const std::string &content, std::string &error) {
    std::ofstream out(path, std::ios::binary);
    if (!out) {
        error = "failed to write file '" + path + "'";
        return false;
    }
    out << content;
    return true;
}

std::string replaceExtension(const std::string &path, const std::string &newExt) {
    std::filesystem::path p(path);
    p.replace_extension(newExt);
    return p.string();
}

std::string quoteCommandArg(const std::string &arg) {
    std::string quoted = "\"";
    for (char c : arg) {
        if (c == '\\' || c == '"') {
            quoted.push_back('\\');
        }
        quoted.push_back(c);
    }
    quoted.push_back('"');
    return quoted;
}

} // namespace hyc
