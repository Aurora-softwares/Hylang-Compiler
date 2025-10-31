#include "object_emit.hpp"

#include <llvm/IR/LegacyPassManager.h>
#include <llvm/IR/Module.h>
#include <llvm/MC/TargetRegistry.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/Target/TargetMachine.h>
#include <llvm/Target/TargetOptions.h>

#include <memory>

namespace hydrogenc {

bool emit_object(llvm::Module& module, const std::filesystem::path& path, std::string& error) {
    std::string triple = module.getTargetTriple();
    if (triple.empty()) {
        triple = "x86_64-pc-windows-msvc";
        module.setTargetTriple(triple);
    }

    std::string err;
    const llvm::Target* target = llvm::TargetRegistry::lookupTarget(triple, err);
    if (!target) {
        error = err;
        return false;
    }

    llvm::TargetOptions opts;
    auto target_machine = std::unique_ptr<llvm::TargetMachine>(
        target->createTargetMachine(triple, "x86-64", "", opts, std::nullopt, std::nullopt, llvm::CodeGenOpt::Default));
    module.setDataLayout(target_machine->createDataLayout());

    std::error_code ec;
    llvm::raw_fd_ostream dest(path.string(), ec, llvm::sys::fs::OF_None);
    if (ec) {
        error = ec.message();
        return false;
    }

    llvm::legacy::PassManager pass;
    if (target_machine->addPassesToEmitFile(pass, dest, nullptr, llvm::CGFT_ObjectFile)) {
        error = "target does not support object emission";
        return false;
    }

    pass.run(module);
    dest.flush();
    return true;
}

} // namespace hydrogenc
