#include "Codegen.h"

#include <optional>
#include <string>
#include <system_error>

#include <llvm/ADT/Triple.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>
#include <llvm/IR/Verifier.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/Host.h>
#include <llvm/Support/Program.h>
#include <llvm/Support/TargetRegistry.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/Target/TargetMachine.h>
#include <llvm/Target/TargetOptions.h>

namespace hy {
namespace {

void initializeLLVM() {
    static bool initialized = false;
    if (initialized) {
        return;
    }
    initialized = true;
    llvm::InitializeNativeTarget();
    llvm::InitializeNativeTargetAsmPrinter();
    llvm::InitializeNativeTargetAsmParser();
}

} // namespace

CodeGenerator::CodeGenerator(DiagnosticEngine &diag)
    : diag_(diag), context_(std::make_unique<llvm::LLVMContext>()) {
    initializeLLVM();
}

CodeGenerator::~CodeGenerator() = default;

std::unique_ptr<llvm::Module> CodeGenerator::codegen(const ast::Module &module, const std::string &name) {
    if (!module.ns) {
        diag_.error("expected a namespace declaration");
        return nullptr;
    }
    if (module.ns->functions.empty()) {
        diag_.error("namespace must contain at least one function");
        return nullptr;
    }
    const auto &fn = *module.ns->functions.front();
    if (fn.name != "main") {
        diag_.error("expected entry function 'main'");
        return nullptr;
    }

    auto irModule = std::make_unique<llvm::Module>(name, *context_);
    irModule->setTargetTriple(llvm::sys::getDefaultTargetTriple());

    llvm::IRBuilder<> builder(*context_);
    auto *fnType = llvm::FunctionType::get(builder.getInt32Ty(), false);
    auto *function = llvm::Function::Create(fnType, llvm::Function::ExternalLinkage, "main", irModule.get());

    auto *entry = llvm::BasicBlock::Create(*context_, "entry", function);
    builder.SetInsertPoint(entry);

    int returnValue = extractReturnValue(fn);
    builder.CreateRet(builder.getInt32(returnValue));

    if (llvm::verifyFunction(*function, &llvm::errs())) {
        diag_.error("generated function failed verification");
        return nullptr;
    }

    return irModule;
}

void CodeGenerator::printIR(llvm::Module &module, llvm::raw_ostream &out) {
    module.print(out, nullptr);
}

bool CodeGenerator::emitObject(llvm::Module &module, const std::string &path) {
    std::string error;
    auto targetTriple = llvm::Triple(module.getTargetTriple());
    if (targetTriple.str().empty()) {
        targetTriple = llvm::Triple(llvm::sys::getDefaultTargetTriple());
        module.setTargetTriple(targetTriple.str());
    }

    const llvm::Target *target = llvm::TargetRegistry::lookupTarget(targetTriple.str(), error);
    if (!target) {
        diag_.error("unable to find target: " + error);
        return false;
    }

    llvm::TargetOptions opt;
    auto relocModel = std::optional<llvm::Reloc::Model>();
    std::unique_ptr<llvm::TargetMachine> targetMachine(
        target->createTargetMachine(targetTriple.str(), "generic", "", opt, relocModel));

    module.setDataLayout(targetMachine->createDataLayout());

    llvm::SmallVector<char, 0> buffer;
    llvm::raw_svector_ostream os(buffer);

    llvm::legacy::PassManager pass;
    if (targetMachine->addPassesToEmitFile(pass, os, nullptr, llvm::CGFT_ObjectFile)) {
        diag_.error("target machine cannot emit object file");
        return false;
    }
    pass.run(module);

    std::error_code ec;
    llvm::raw_fd_ostream file(path, ec, llvm::sys::fs::OF_None);
    if (ec) {
        diag_.error("failed to open object file: " + ec.message());
        return false;
    }
    file.write(buffer.data(), buffer.size());
    file.flush();

    return true;
}

bool CodeGenerator::linkExecutable(const std::string &objectPath, const std::string &outputPath) {
    auto clangPath = llvm::sys::findProgramByName("clang");
    if (!clangPath) {
        diag_.error("unable to find 'clang' in PATH for linking");
        return false;
    }

    llvm::SmallVector<llvm::StringRef, 8> args;
    args.push_back(*clangPath);
    args.push_back(objectPath);
    args.push_back("-fuse-ld=lld");
    args.push_back("-o");
    args.push_back(outputPath);

    int result = llvm::sys::ExecuteAndWait(*clangPath, args);
    if (result != 0) {
        diag_.error("linker failed with exit code " + std::to_string(result));
        return false;
    }
    return true;
}

int CodeGenerator::extractReturnValue(const ast::FuncDecl &fn) const {
    if (!fn.body || fn.body->statements.empty()) {
        diag_.error("function body missing return statement");
        return 0;
    }
    const auto *ret = dynamic_cast<ast::ReturnStmt *>(fn.body->statements.front().get());
    if (!ret) {
        diag_.error("first statement must be a return");
        return 0;
    }
    const auto *literal = dynamic_cast<ast::IntegerLiteral *>(ret->value.get());
    if (!literal) {
        diag_.error("return expression must be an integer literal");
        return 0;
    }
    return literal->value;
}

} // namespace hy
