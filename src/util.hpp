#pragma once

#include <string>

namespace hyc {

bool readFile(const std::string &path, std::string &out, std::string &error);
bool writeFile(const std::string &path, const std::string &content, std::string &error);
std::string replaceExtension(const std::string &path, const std::string &newExt);
std::string quoteCommandArg(const std::string &arg);

}
