#pragma once

#include "tokens.hpp"

#include <memory>
#include <string>
#include <vector>

namespace hyc {

struct Diagnostic {
    enum class Level {
        Error,
        Warning,
        Note,
    } level = Level::Error;

    std::string message;
    SourceLocation location;
    std::string lineText;
    unsigned underlineStart = 0;
    unsigned underlineLength = 1;
};

class Diagnostics {
  public:
    void error(const SourceLocation &loc, const std::string &lineText, unsigned start, unsigned length, std::string message);
    bool hasErrors() const { return m_hasErrors; }
    const std::vector<Diagnostic> &messages() const { return m_messages; }
    void printToStderr() const;

  private:
    std::vector<Diagnostic> m_messages;
    bool m_hasErrors = false;
};

} // namespace hyc
