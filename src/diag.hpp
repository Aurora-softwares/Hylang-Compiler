#pragma once

#include "tokens.hpp"

#include <functional>
#include <memory>
#include <ostream>
#include <string>
#include <vector>

namespace hyc {

struct SourceBuffer {
    std::string filename;
    std::vector<std::string> lines;
};

class Diagnostics {
  public:
    using Sink = std::function<void(const std::string&)>;

    explicit Diagnostics(Sink sink = default_sink());

    void add_buffer(std::shared_ptr<SourceBuffer> buffer);

    void error(const SourceLocation& loc, const std::string& message,
               std::size_t highlight_length = 1);

    bool has_errors() const { return has_errors_; }

  private:
    static Sink default_sink();

    std::string format_message(const SourceLocation& loc,
                               const std::string& message,
                               std::size_t highlight_length) const;

    std::vector<std::shared_ptr<SourceBuffer>> buffers_;
    Sink sink_;
    bool has_errors_ = false;
};

} // namespace hyc
