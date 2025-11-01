#include "linker.hpp"

#include <cstdlib>
#include <filesystem>

#include <llvm/ADT/SmallVector.h>
#include <llvm/Support/Program.h>
#include <llvm/Support/raw_ostream.h>

namespace {
std::string joinPath(const std::string &lhs, const std::string &rhs) {
    std::filesystem::path path(lhs);
    path /= rhs;
    return path.string();
}
}

std::string findLldLink() {
    if (const char *overridePath = std::getenv("HYDROGENC_LLD")) {
        return std::string(overridePath);
    }
    if (const char *bindir = std::getenv("LLVM_BINDIR")) {
        auto candidate = joinPath(bindir, "lld-link.exe");
        if (std::filesystem::exists(candidate)) {
            return candidate;
        }
        candidate = joinPath(bindir, "lld-link");
        if (std::filesystem::exists(candidate)) {
            return candidate;
        }
    }
    auto result = llvm::sys::findProgramByName("lld-link");
    if (!result) {
        result = llvm::sys::findProgramByName("lld-link.exe");
    }
    if (result) {
        return *result;
    }
    return {};
}

bool linkExecutable(const std::string &objectPath,
                    const std::string &outputPath,
                    std::string &errorMessage,
                    bool verbose,
                    const std::vector<std::string> &librarySearchPaths,
                    const std::vector<std::string> &additionalLibraries) {
    std::string lldPath = findLldLink();
    if (lldPath.empty()) {
        errorMessage = "unable to locate lld-link; set HYDROGENC_LLD or ensure it is in PATH";
        return false;
    }

    std::vector<std::string> args;
    args.push_back(lldPath);
    args.emplace_back("/nologo");
    args.emplace_back("/entry:main");
    args.emplace_back("/subsystem:console");
    args.emplace_back("/defaultlib:kernel32.lib");
    for (const auto &path : librarySearchPaths) {
        args.push_back("/libpath:" + path);
    }
    for (const auto &lib : additionalLibraries) {
        args.push_back(lib);
    }
    args.push_back("/out:" + outputPath);
    args.push_back(objectPath);

    llvm::SmallVector<llvm::StringRef, 16> argRefs;
    for (const auto &arg : args) {
        argRefs.emplace_back(arg);
    }

    if (verbose) {
        llvm::errs() << "[hydrogenc] " << lldPath;
        for (std::size_t i = 1; i < args.size(); ++i) {
            llvm::errs() << ' ' << args[i];
        }
        llvm::errs() << '\n';
    }

    int result = llvm::sys::ExecuteAndWait(lldPath, argRefs);
    if (result != 0) {
        errorMessage = "lld-link exited with code " + std::to_string(result);
        return false;
    }
    return true;
}
