#pragma once

#include <string>
#include <vector>

bool linkExecutable(const std::string &objectPath,
                    const std::string &outputPath,
                    std::string &errorMessage,
                    bool verbose,
                    const std::vector<std::string> &librarySearchPaths = {},
                    const std::vector<std::string> &additionalLibraries = {});

std::string findLldLink();
