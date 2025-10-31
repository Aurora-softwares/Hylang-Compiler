#include "winrt.hpp"

#include <llvm/IR/BasicBlock.h>
#include <llvm/IR/Constants.h>
#include <llvm/IR/DerivedTypes.h>
#include <llvm/IR/Function.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/Module.h>
#include <llvm/IR/Type.h>
#include <llvm/Support/Casting.h>

namespace hydrogenc::winrt {

namespace {

llvm::Function* declare_get_std_handle(llvm::Module& module) {
    auto& ctx = module.getContext();
    auto* func_type = llvm::FunctionType::get(llvm::Type::getInt8PtrTy(ctx), {llvm::Type::getInt32Ty(ctx)}, false);
    auto callee = module.getOrInsertFunction("GetStdHandle", func_type);
    auto* func = llvm::cast<llvm::Function>(callee.getCallee());
    func->setCallingConv(llvm::CallingConv::X86_64_Win64);
    func->setDLLStorageClass(llvm::GlobalValue::DLLImportStorageClass);
    return func;
}

llvm::Function* declare_write_file(llvm::Module& module) {
    auto& ctx = module.getContext();
    auto* i32 = llvm::Type::getInt32Ty(ctx);
    auto* i8_ptr = llvm::Type::getInt8PtrTy(ctx);
    auto* lp_written = llvm::PointerType::get(i32, 0);
    auto* func_type = llvm::FunctionType::get(i32, {i8_ptr, i8_ptr, i32, lp_written, i8_ptr}, false);
    auto callee = module.getOrInsertFunction("WriteFile", func_type);
    auto* func = llvm::cast<llvm::Function>(callee.getCallee());
    func->setCallingConv(llvm::CallingConv::X86_64_Win64);
    func->setDLLStorageClass(llvm::GlobalValue::DLLImportStorageClass);
    return func;
}

llvm::Function* create_hy_print(llvm::Module& module) {
    auto& ctx = module.getContext();
    auto* i32 = llvm::Type::getInt32Ty(ctx);
    auto* i8 = llvm::Type::getInt8Ty(ctx);
    auto* i1 = llvm::Type::getInt1Ty(ctx);
    auto* i64 = llvm::Type::getInt64Ty(ctx);
    auto* i8_ptr = llvm::Type::getInt8PtrTy(ctx);
    auto* hy_type = llvm::FunctionType::get(i32, {i32}, false);

    auto* hy_print = llvm::Function::Create(hy_type, llvm::GlobalValue::InternalLinkage, "hy_print_i32", module);
    auto* entry = llvm::BasicBlock::Create(ctx, "entry", hy_print);
    auto* loop = llvm::BasicBlock::Create(ctx, "loop", hy_print);
    auto* loop_check = llvm::BasicBlock::Create(ctx, "loop.check", hy_print);
    auto* after_loop = llvm::BasicBlock::Create(ctx, "afterloop", hy_print);
    auto* neg_block = llvm::BasicBlock::Create(ctx, "neg", hy_print);
    auto* cont_block = llvm::BasicBlock::Create(ctx, "cont", hy_print);
    auto* exit_block = llvm::BasicBlock::Create(ctx, "exit", hy_print);

    llvm::IRBuilder<> builder(entry);

    auto* buffer_type = llvm::ArrayType::get(i8, 16);
    auto* buffer = builder.CreateAlloca(buffer_type, nullptr, "buffer");
    auto* ptr_alloca = builder.CreateAlloca(i8_ptr, nullptr, "ptr");
    auto* value_alloca = builder.CreateAlloca(i64, nullptr, "value");
    auto* negative_alloca = builder.CreateAlloca(i1, nullptr, "neg");

    auto* newline_ptr = builder.CreateInBoundsGEP(buffer_type, buffer, {builder.getInt32(0), builder.getInt32(15)}, "newline_ptr");
    builder.CreateStore(builder.getInt8('\n'), newline_ptr);

    llvm::Value* one_before_newline = builder.CreateInBoundsGEP(builder.getInt8Ty(), newline_ptr, builder.getInt32(-1));
    builder.CreateStore(one_before_newline, ptr_alloca);

    llvm::Value* input = hy_print->getArg(0);
    auto* wide_input = builder.CreateSExt(input, i64, "wide");
    auto* is_negative = builder.CreateICmpSLT(input, builder.getInt32(0));
    builder.CreateStore(is_negative, negative_alloca);
    auto* abs_val = builder.CreateSelect(is_negative, builder.CreateNeg(wide_input), wide_input);
    builder.CreateStore(abs_val, value_alloca);

    builder.CreateBr(loop);

    builder.SetInsertPoint(loop);
    auto* current_val = builder.CreateLoad(i64, value_alloca, "current");
    auto* digit = builder.CreateSRem(current_val, builder.getInt64(10), "digit");
    auto* digit32 = builder.CreateTrunc(digit, builder.getInt32Ty(), "digit32");
    auto* char_val = builder.CreateAdd(digit32, builder.getInt32('0'), "char_val");
    auto* char_byte = builder.CreateTrunc(char_val, i8, "char_byte");
    auto* current_ptr = builder.CreateLoad(i8_ptr, ptr_alloca, "cur_ptr");
    builder.CreateStore(char_byte, current_ptr);
    auto* prev_ptr = builder.CreateInBoundsGEP(builder.getInt8Ty(), current_ptr, builder.getInt32(-1), "prev_ptr");
    builder.CreateStore(prev_ptr, ptr_alloca);
    auto* divided = builder.CreateSDiv(current_val, builder.getInt64(10), "divided");
    builder.CreateStore(divided, value_alloca);
    builder.CreateBr(loop_check);

    builder.SetInsertPoint(loop_check);
    auto* next_val = builder.CreateLoad(i64, value_alloca, "next");
    auto* continue_cond = builder.CreateICmpNE(next_val, builder.getInt64(0));
    builder.CreateCondBr(continue_cond, loop, after_loop);

    builder.SetInsertPoint(after_loop);
    auto* was_negative = builder.CreateLoad(i1, negative_alloca, "was_neg");
    builder.CreateCondBr(was_negative, neg_block, cont_block);

    builder.SetInsertPoint(neg_block);
    auto* neg_ptr = builder.CreateLoad(i8_ptr, ptr_alloca, "neg_ptr");
    builder.CreateStore(builder.getInt8('-'), neg_ptr);
    auto* before_neg = builder.CreateInBoundsGEP(builder.getInt8Ty(), neg_ptr, builder.getInt32(-1), "before_neg");
    builder.CreateStore(before_neg, ptr_alloca);
    builder.CreateBr(cont_block);

    builder.SetInsertPoint(cont_block);
    auto* start_ptr_raw = builder.CreateLoad(i8_ptr, ptr_alloca, "start_raw");
    auto* start_ptr = builder.CreateInBoundsGEP(builder.getInt8Ty(), start_ptr_raw, builder.getInt32(1), "start");
    auto* buffer_end = builder.CreateInBoundsGEP(buffer_type, buffer, {builder.getInt32(0), builder.getInt32(16)}, "buffer_end");
    auto* start_int = builder.CreatePtrToInt(start_ptr, builder.getInt64Ty(), "start_int");
    auto* end_int = builder.CreatePtrToInt(buffer_end, builder.getInt64Ty(), "end_int");
    auto* len64 = builder.CreateSub(end_int, start_int, "len64");
    auto* length = builder.CreateTrunc(len64, builder.getInt32Ty(), "length");

    auto* get_std_handle = declare_get_std_handle(module);
    auto* write_file = declare_write_file(module);

    auto* handle = builder.CreateCall(get_std_handle, {builder.getInt32(-11)}, "stdout_handle");
    auto* null_written = llvm::ConstantPointerNull::get(llvm::PointerType::get(builder.getInt32Ty(), 0));
    builder.CreateCall(write_file, {handle, start_ptr, length, null_written, llvm::ConstantPointerNull::get(i8_ptr)});
    builder.CreateBr(exit_block);

    builder.SetInsertPoint(exit_block);
    builder.CreateRet(builder.getInt32(0));

    return hy_print;
}

void create_public_print(llvm::Module& module, llvm::Function* hy_print) {
    auto& ctx = module.getContext();
    auto* i32 = llvm::Type::getInt32Ty(ctx);
    auto* func_type = llvm::FunctionType::get(i32, {i32}, false);
    auto* print = module.getFunction("Print");
    if (!print) {
        print = llvm::Function::Create(func_type, llvm::GlobalValue::ExternalLinkage, "Print", module);
        auto* entry = llvm::BasicBlock::Create(ctx, "entry", print);
        llvm::IRBuilder<> builder(entry);
        builder.CreateCall(hy_print, {print->getArg(0)});
        builder.CreateRet(builder.getInt32(0));
    }
}

} // namespace

void inject_runtime(llvm::Module& module) {
    if (module.getFunction("hy_print_i32")) {
        return;
    }
    auto* hy_print = create_hy_print(module);
    create_public_print(module, hy_print);
}

} // namespace hydrogenc::winrt
