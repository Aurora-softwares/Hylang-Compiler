#include "linker.hpp"

#include <cstdlib>
#include <sstream>

namespace hyc {

bool Linker::link(const LinkOptions& opts, std::string& error_message) const {
    std::string lld = opts.lld_path.empty() ? "lld-link" : opts.lld_path;
    std::ostringstream cmd;
    cmd << '"' << lld << '"';
    cmd << " /nologo /nodefaultlib /entry:hy_entry /subsystem:console ";
    if (opts.verbose) {
        cmd << "/verbose ";
    }
    cmd << '"' << opts.object_path << '"';
    cmd << " kernel32.lib ";
    cmd << "/out:" << '"' << opts.output_path << '"';

    int result = std::system(cmd.str().c_str());
    if (result != 0) {
        error_message = "lld-link failed with exit code " + std::to_string(result);
        return false;
    }
    return true;
}

} // namespace hyc
