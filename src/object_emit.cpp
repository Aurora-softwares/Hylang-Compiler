#include "object_emit.hpp"

#include <memory>
#include <optional>

#include <llvm/IR/LegacyPassManager.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/Host.h>
#include <llvm/Support/TargetRegistry.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/Target/TargetMachine.h>

namespace {
void ensureTargetInitialized() {
    static bool initialized = false;
    if (!initialized) {
        llvm::InitializeNativeTarget();
        llvm::InitializeNativeTargetAsmPrinter();
        llvm::InitializeNativeTargetAsmParser();
        initialized = true;
    }
}
}

bool emitObjectFile(llvm::Module &module, const std::string &path, std::string &errorMessage) {
    ensureTargetInitialized();

    std::string triple = module.getTargetTriple();
    if (triple.empty()) {
        triple = llvm::sys::getDefaultTargetTriple();
        module.setTargetTriple(triple);
    }

    std::string lookupError;
    const llvm::Target *target = llvm::TargetRegistry::lookupTarget(triple, lookupError);
    if (!target) {
        errorMessage = lookupError;
        return false;
    }

    llvm::TargetOptions options;
    auto targetMachine = std::unique_ptr<llvm::TargetMachine>(
        target->createTargetMachine(triple, "generic", "", options, std::nullopt));
    module.setDataLayout(targetMachine->createDataLayout());

    std::error_code ec;
    llvm::raw_fd_ostream dest(path, ec, llvm::sys::fs::OF_None);
    if (ec) {
        errorMessage = ec.message();
        return false;
    }

    llvm::legacy::PassManager pass;
    if (targetMachine->addPassesToEmitFile(pass, dest, nullptr, llvm::CGFT_ObjectFile)) {
        errorMessage = "target does not support object emission";
        return false;
    }

    pass.run(module);
    dest.flush();
    return true;
}
