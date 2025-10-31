#pragma once

#include "tokens.hpp"

#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace hydrogenc {

std::optional<std::string> read_file(const std::filesystem::path& path);
bool write_file(const std::filesystem::path& path, std::string_view data, std::string& error);
std::vector<std::string> split_lines(std::string_view text);
std::string to_lower_copy(std::string_view text);
std::filesystem::path change_extension(const std::filesystem::path& path, const std::string& ext);
std::filesystem::path make_temporary_obj(const std::string& prefix, std::string& error);

} // namespace hydrogenc
