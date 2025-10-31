#include "linker.hpp"

#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <vector>

#include <llvm/ADT/SmallVector.h>
#include <llvm/ADT/StringRef.h>
#include <llvm/Support/Process.h>
#include <llvm/Support/Program.h>

namespace hydrogenc {

static std::string find_lld_link() {
    if (const char* env = std::getenv("HYDROGENC_LLD_LINK")) {
        return env;
    }
    if (auto path = llvm::sys::Process::FindProgramByName("lld-link")) {
        return *path;
    }
    return {};
}

bool link_executable(const std::filesystem::path& object_file,
                     const std::filesystem::path& exe_path,
                     std::string& error,
                     bool verbose) {
    auto lld_path = find_lld_link();
    if (lld_path.empty()) {
        error = "unable to locate lld-link; ensure it is on PATH or set HYDROGENC_LLD_LINK";
        return false;
    }

    std::vector<std::string> args_storage;
    args_storage.push_back(lld_path);
    args_storage.push_back("/nologo");
    args_storage.push_back("/machine:x64");
    args_storage.push_back("/nodefaultlib");
    args_storage.push_back("/entry:main");
    args_storage.push_back("/subsystem:console");
    args_storage.push_back("/defaultlib:kernel32.lib");
    args_storage.push_back("/out:" + exe_path.string());
    args_storage.push_back(object_file.string());

    llvm::SmallVector<llvm::StringRef, 16> args;
    for (const auto& s : args_storage) {
        args.push_back(s);
    }

    if (verbose) {
        std::cerr << "[link]";
        for (const auto& s : args_storage) {
            std::cerr << ' ' << s;
        }
        std::cerr << "\n";
    }

    int result = llvm::sys::ExecuteAndWait(lld_path, args);
    if (result != 0) {
        error = "lld-link failed with exit code " + std::to_string(result);
        return false;
    }

    return true;
}

} // namespace hydrogenc
