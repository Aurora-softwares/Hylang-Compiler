#include "object_emit.hpp"

#include <llvm/IR/LegacyPassManager.h>
#include <llvm/MC/TargetRegistry.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/Target/TargetMachine.h>

#include <memory>
#include <optional>

namespace hyc {

bool emitObjectFile(llvm::Module &module, const std::string &path, std::string &error) {
    std::string triple = module.getTargetTriple();
    if (triple.empty()) {
        triple = "x86_64-pc-windows-msvc";
        module.setTargetTriple(triple);
    }

    std::string lookupError;
    const llvm::Target *target = llvm::TargetRegistry::lookupTarget(triple, lookupError);
    if (!target) {
        error = lookupError;
        return false;
    }

    llvm::TargetOptions options;
    auto targetMachine = std::unique_ptr<llvm::TargetMachine>(target->createTargetMachine(
        triple, "x86-64", "", options, std::nullopt, std::nullopt, llvm::CodeGenOptLevel::Default));
    if (!targetMachine) {
        error = "failed to create target machine";
        return false;
    }

    module.setDataLayout(targetMachine->createDataLayout());

    std::error_code ec;
    llvm::raw_fd_ostream dest(path, ec, llvm::sys::fs::OF_None);
    if (ec) {
        error = ec.message();
        return false;
    }

    llvm::legacy::PassManager pass;
    if (targetMachine->addPassesToEmitFile(pass, dest, nullptr, llvm::CGFT_ObjectFile)) {
        error = "target does not support object emission";
        return false;
    }

    pass.run(module);
    dest.flush();
    return true;
}

} // namespace hyc
