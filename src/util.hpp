#pragma once

#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace hyc {

std::string to_lower_copy(std::string_view text);

std::vector<std::string> split_lines(const std::string& content);

std::optional<std::string> read_file(const std::string& path);

} // namespace hyc
