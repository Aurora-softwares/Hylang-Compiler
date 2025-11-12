#pragma once

#include <string>

#include "Codegen.h"
#include "Error.h"

namespace hy {

class CLI {
public:
    explicit CLI(DiagnosticEngine &diag);

    int run(int argc, char **argv);

private:
    int handleIR(const std::string &path);
    int handleBuild(const std::string &path);
    std::string loadFile(const std::string &path);

    DiagnosticEngine &diag_;
};

} // namespace hy
