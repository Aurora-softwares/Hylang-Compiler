#include "linker.hpp"

#include "util.hpp"

#include <cstdlib>
#include <cstdio>
#include <vector>
#include <sstream>

namespace hyc {

bool linkExecutable(const std::string &objectPath, const std::string &outputPath, const std::vector<std::string> &libraries,
                    const std::string &lldPath, bool verbose, std::string &error) {
    std::string linker = lldPath.empty() ? "lld-link" : lldPath;
    std::ostringstream command;
    command << quoteCommandArg(linker);
    command << " /nologo";
    command << " /out:" << quoteCommandArg(outputPath);
    command << ' ' << quoteCommandArg(objectPath);
    command << " /defaultlib:kernel32.lib";
    command << " /subsystem:console";
    for (const auto &lib : libraries) {
        command << ' ' << quoteCommandArg(lib);
    }

    auto cmdStr = command.str();
    if (verbose) {
        std::printf("[link] %s\n", cmdStr.c_str());
    }

    int result = std::system(cmdStr.c_str());
    if (result != 0) {
        error = "lld-link failed with exit code " + std::to_string(result);
        return false;
    }
    return true;
}

} // namespace hyc
