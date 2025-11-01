#pragma once

#include <string>
#include <vector>

namespace hyc {

bool linkExecutable(const std::string &objectPath, const std::string &outputPath, const std::vector<std::string> &libraries,
                    const std::string &lldPath, bool verbose, std::string &error);

}
