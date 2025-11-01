#pragma once

#include <string>

namespace hyc {

struct LinkOptions {
    std::string lld_path;
    std::string object_path;
    std::string output_path;
    bool verbose = false;
};

class Linker {
  public:
    bool link(const LinkOptions& opts, std::string& error_message) const;
};

} // namespace hyc
