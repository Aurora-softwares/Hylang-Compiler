#include "object_emit.hpp"

#include <llvm/IR/LegacyPassManager.h>
#include <llvm/IR/Module.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/Host.h>
#include <llvm/Support/TargetRegistry.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Target/TargetMachine.h>
#include <llvm/Target/TargetOptions.h>

#include <memory>
#include <optional>

namespace hyc {

ObjectEmitter::ObjectEmitter(llvm::Module& module) : module_(module) {}

bool ObjectEmitter::emit(const std::string& path, std::string& error_message) {
    static bool initialized = false;
    if (!initialized) {
        llvm::InitializeAllTargetInfos();
        llvm::InitializeAllTargets();
        llvm::InitializeAllTargetMCs();
        llvm::InitializeAllAsmParsers();
        llvm::InitializeAllAsmPrinters();
        initialized = true;
    }

    std::string triple = "x86_64-pc-windows-msvc";
    module_.setTargetTriple(triple);

    std::string lookup_error;
    const llvm::Target* target =
        llvm::TargetRegistry::lookupTarget(triple, lookup_error);
    if (!target) {
        error_message = lookup_error;
        return false;
    }

    llvm::TargetOptions options;
    auto reloc_model = std::optional<llvm::Reloc::Model>(llvm::Reloc::Static);
    auto tm = std::unique_ptr<llvm::TargetMachine>(
        target->createTargetMachine(triple, "x86-64", "", options, reloc_model));
    if (!tm) {
        error_message = "failed to create target machine";
        return false;
    }

    module_.setDataLayout(tm->createDataLayout());

    std::error_code ec;
    llvm::raw_fd_ostream dest(path, ec, llvm::sys::fs::OF_None);
    if (ec) {
        error_message = ec.message();
        return false;
    }

    llvm::legacy::PassManager pass;
    if (tm->addPassesToEmitFile(pass, dest, nullptr, llvm::CGFT_ObjectFile)) {
        error_message = "target machine cannot emit object file";
        return false;
    }

    pass.run(module_);
    dest.flush();
    return true;
}

} // namespace hyc
