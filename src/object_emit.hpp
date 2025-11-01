#pragma once

#include <string>

namespace llvm {
class Module;
}

namespace hyc {

class ObjectEmitter {
  public:
    explicit ObjectEmitter(llvm::Module& module);

    bool emit(const std::string& path, std::string& error_message);

  private:
    llvm::Module& module_;
};

} // namespace hyc
