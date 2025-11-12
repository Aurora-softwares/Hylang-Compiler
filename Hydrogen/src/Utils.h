#pragma once

#include <cctype>
#include <string>

namespace hy {

inline bool isIdentifierStart(char c) {
    return std::isalpha(static_cast<unsigned char>(c)) || c == '_';
}

inline bool isIdentifierPart(char c) {
    return isIdentifierStart(c) || std::isdigit(static_cast<unsigned char>(c));
}

inline bool isDigit(char c) {
    return std::isdigit(static_cast<unsigned char>(c));
}

} // namespace hy
