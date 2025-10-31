#pragma once

#include <filesystem>
#include <string>

namespace hydrogenc {

bool link_executable(const std::filesystem::path& object_file,
                     const std::filesystem::path& exe_path,
                     std::string& error,
                     bool verbose);

}
