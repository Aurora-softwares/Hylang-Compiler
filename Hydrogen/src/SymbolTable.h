#pragma once

#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace hy {

class SymbolTable {
public:
    void enterScope() { scopes_.emplace_back(); }
    void exitScope() {
        if (!scopes_.empty()) {
            scopes_.pop_back();
        }
    }

    void declare(const std::string &name) {
        if (scopes_.empty()) {
            enterScope();
        }
        scopes_.back()[name] = true;
    }

    bool lookup(const std::string &name) const {
        for (auto it = scopes_.rbegin(); it != scopes_.rend(); ++it) {
            if (it->count(name)) {
                return true;
            }
        }
        return false;
    }

private:
    std::vector<std::unordered_map<std::string, bool>> scopes_;
};

} // namespace hy
