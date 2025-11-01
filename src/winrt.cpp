#include "winrt.hpp"

#include <llvm/IR/BasicBlock.h>
#include <llvm/IR/Constants.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/Type.h>

namespace hyc {

RuntimeSupport::RuntimeSupport(llvm::Module& module) : module_(module) {}

void RuntimeSupport::ensure_runtime() {
    ensure_print_wrapper();
    ensure_entry_function();
}

llvm::Function* RuntimeSupport::get_print_wrapper() {
    return ensure_print_wrapper();
}

llvm::Function* RuntimeSupport::declare_get_std_handle() {
    auto& ctx = module_.getContext();
    auto* fn = module_.getFunction("GetStdHandle");
    if (fn) {
        return fn;
    }
    auto* fn_type = llvm::FunctionType::get(llvm::Type::getInt64Ty(ctx),
                                            {llvm::Type::getInt32Ty(ctx)}, false);
    return llvm::cast<llvm::Function>(module_.getOrInsertFunction("GetStdHandle", fn_type).getCallee());
}

llvm::Function* RuntimeSupport::declare_write_file() {
    auto& ctx = module_.getContext();
    auto* fn = module_.getFunction("WriteFile");
    if (fn) {
        return fn;
    }
    auto* fn_type = llvm::FunctionType::get(
        llvm::Type::getInt32Ty(ctx),
        {llvm::Type::getInt64Ty(ctx), llvm::Type::getInt8PtrTy(ctx),
         llvm::Type::getInt32Ty(ctx), llvm::Type::getInt32PtrTy(ctx),
         llvm::Type::getInt8PtrTy(ctx)},
        false);
    return llvm::cast<llvm::Function>(module_.getOrInsertFunction("WriteFile", fn_type).getCallee());
}

llvm::Function* RuntimeSupport::declare_exit_process() {
    auto& ctx = module_.getContext();
    auto* fn = module_.getFunction("ExitProcess");
    if (fn) {
        return fn;
    }
    auto* fn_type =
        llvm::FunctionType::get(llvm::Type::getVoidTy(ctx),
                                 {llvm::Type::getInt32Ty(ctx)}, false);
    return llvm::cast<llvm::Function>(module_.getOrInsertFunction("ExitProcess", fn_type).getCallee());
}

llvm::Function* RuntimeSupport::ensure_print_function() {
    if (print_intrinsic_) {
        return print_intrinsic_;
    }

    auto& ctx = module_.getContext();
    auto* fn_type = llvm::FunctionType::get(llvm::Type::getVoidTy(ctx),
                                            {llvm::Type::getInt32Ty(ctx)}, false);
    auto callee = module_.getOrInsertFunction("hy_print_i32", fn_type);
    auto* fn = llvm::cast<llvm::Function>(callee.getCallee());
    if (!fn->empty()) {
        print_intrinsic_ = fn;
        return fn;
    }

    llvm::IRBuilder<> builder(ctx);
    llvm::BasicBlock* entry = llvm::BasicBlock::Create(ctx, "entry", fn);
    builder.SetInsertPoint(entry);

    auto* buf_type = llvm::ArrayType::get(llvm::Type::getInt8Ty(ctx), 32);
    auto* buf = builder.CreateAlloca(buf_type, nullptr, "buf");
    auto zero = builder.getInt32(0);
    auto* end_ptr = builder.CreateInBoundsGEP(
        buf_type, buf, {zero, builder.getInt32(31)}, "endptr");
    builder.CreateStore(builder.getInt8('\n'), end_ptr);
    auto* cur_ptr_alloca = builder.CreateAlloca(llvm::Type::getInt8PtrTy(ctx), nullptr,
                                                "cur");
    builder.CreateStore(end_ptr, cur_ptr_alloca);

    auto* value_alloca = builder.CreateAlloca(llvm::Type::getInt32Ty(ctx), nullptr,
                                              "value");
    builder.CreateStore(fn->getArg(0), value_alloca);

    auto* neg_flag = builder.CreateICmpSLT(fn->getArg(0), builder.getInt32(0),
                                           "isneg");
    auto* negated = builder.CreateNeg(fn->getArg(0));
    auto* abs_value = builder.CreateSelect(neg_flag, negated, fn->getArg(0));
    builder.CreateStore(abs_value, value_alloca);

    auto* is_zero = builder.CreateICmpEQ(abs_value, builder.getInt32(0));
    llvm::BasicBlock* zero_block = llvm::BasicBlock::Create(ctx, "zero", fn);
    llvm::BasicBlock* digits_entry = llvm::BasicBlock::Create(ctx, "digits_entry", fn);
    llvm::BasicBlock* after_digits =
        llvm::BasicBlock::Create(ctx, "after_digits", fn);
    builder.CreateCondBr(is_zero, zero_block, digits_entry);

    // zero block
    builder.SetInsertPoint(zero_block);
    auto* cur_ptr_z = builder.CreateLoad(llvm::Type::getInt8PtrTy(ctx), cur_ptr_alloca);
    auto* dec_z = builder.CreateInBoundsGEP(builder.getInt8Ty(), cur_ptr_z,
                                            builder.getInt32(-1));
    builder.CreateStore(dec_z, cur_ptr_alloca);
    builder.CreateStore(builder.getInt8('0'), dec_z);
    builder.CreateBr(after_digits);

    // digits loop
    builder.SetInsertPoint(digits_entry);
    llvm::BasicBlock* digits_loop = llvm::BasicBlock::Create(ctx, "digits_loop", fn);
    builder.CreateBr(digits_loop);

    builder.SetInsertPoint(digits_loop);
    auto* cur_val =
        builder.CreateLoad(llvm::Type::getInt32Ty(ctx), value_alloca, "curval");
    auto* digit = builder.CreateURem(cur_val, builder.getInt32(10), "digit");
    auto* div = builder.CreateUDiv(cur_val, builder.getInt32(10), "div");
    builder.CreateStore(div, value_alloca);
    auto* cur_ptr = builder.CreateLoad(llvm::Type::getInt8PtrTy(ctx), cur_ptr_alloca);
    auto* dec = builder.CreateInBoundsGEP(builder.getInt8Ty(), cur_ptr,
                                          builder.getInt32(-1), "dec");
    builder.CreateStore(dec, cur_ptr_alloca);
    auto* char_val = builder.CreateTrunc(
        builder.CreateAdd(digit, builder.getInt32('0')), builder.getInt8Ty());
    builder.CreateStore(char_val, dec);
    auto* cont = builder.CreateICmpNE(div, builder.getInt32(0));
    builder.CreateCondBr(cont, digits_loop, after_digits);

    // after digits
    builder.SetInsertPoint(after_digits);
    auto* neg_check = builder.CreateICmpSLT(fn->getArg(0), builder.getInt32(0));
    llvm::BasicBlock* neg_block = llvm::BasicBlock::Create(ctx, "neg", fn);
    llvm::BasicBlock* after_sign = llvm::BasicBlock::Create(ctx, "after_sign", fn);
    builder.CreateCondBr(neg_check, neg_block, after_sign);

    builder.SetInsertPoint(neg_block);
    auto* cur_ptr_neg = builder.CreateLoad(llvm::Type::getInt8PtrTy(ctx), cur_ptr_alloca);
    auto* dec_neg = builder.CreateInBoundsGEP(builder.getInt8Ty(), cur_ptr_neg,
                                              builder.getInt32(-1));
    builder.CreateStore(dec_neg, cur_ptr_alloca);
    builder.CreateStore(builder.getInt8('-'), dec_neg);
    builder.CreateBr(after_sign);

    builder.SetInsertPoint(after_sign);
    auto* start_ptr = builder.CreateLoad(llvm::Type::getInt8PtrTy(ctx), cur_ptr_alloca);
    auto* start_int = builder.CreatePtrToInt(start_ptr, builder.getInt64Ty());
    auto* end_int = builder.CreatePtrToInt(end_ptr, builder.getInt64Ty());
    auto* diff = builder.CreateSub(end_int, start_int, "len");
    auto* len = builder.CreateTrunc(diff, builder.getInt32Ty());
    auto* total_len = builder.CreateAdd(len, builder.getInt32(1));
    auto* written = builder.CreateAlloca(llvm::Type::getInt32Ty(ctx), nullptr,
                                         "written");
    auto* handle = builder.CreateCall(declare_get_std_handle(),
                                      {builder.getInt32(-11)});
    builder.CreateCall(declare_write_file(),
                       {handle, start_ptr, total_len, written,
                        llvm::ConstantPointerNull::get(
                            llvm::Type::getInt8PtrTy(ctx))});
    builder.CreateRetVoid();

    print_intrinsic_ = fn;
    return fn;
}

llvm::Function* RuntimeSupport::ensure_print_wrapper() {
    if (print_wrapper_) {
        return print_wrapper_;
    }
    auto& ctx = module_.getContext();
    auto* fn_type = llvm::FunctionType::get(llvm::Type::getInt32Ty(ctx),
                                            {llvm::Type::getInt32Ty(ctx)}, false);
    auto callee = module_.getOrInsertFunction("Print", fn_type);
    auto* fn = llvm::cast<llvm::Function>(callee.getCallee());
    if (!fn->empty()) {
        print_wrapper_ = fn;
        return fn;
    }

    llvm::BasicBlock* entry = llvm::BasicBlock::Create(ctx, "entry", fn);
    llvm::IRBuilder<> builder(entry);
    builder.CreateCall(ensure_print_function(), {fn->getArg(0)});
    builder.CreateRet(llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 0));
    print_wrapper_ = fn;
    return fn;
}

llvm::Function* RuntimeSupport::ensure_entry_function() {
    if (entry_function_) {
        return entry_function_;
    }
    auto& ctx = module_.getContext();
    auto* fn_type = llvm::FunctionType::get(llvm::Type::getVoidTy(ctx), {}, false);
    auto callee = module_.getOrInsertFunction("hy_entry", fn_type);
    auto* fn = llvm::cast<llvm::Function>(callee.getCallee());
    if (!fn->empty()) {
        entry_function_ = fn;
        return fn;
    }

    llvm::BasicBlock* entry = llvm::BasicBlock::Create(ctx, "entry", fn);
    llvm::IRBuilder<> builder(entry);
    auto main_callee = module_.getOrInsertFunction(
        "main",
        llvm::FunctionType::get(llvm::Type::getInt32Ty(ctx), {}, false));
    auto* main_fn = llvm::cast<llvm::Function>(main_callee.getCallee());
    auto* result = builder.CreateCall(main_fn);
    builder.CreateCall(declare_exit_process(), {result});
    builder.CreateRetVoid();
    entry_function_ = fn;
    return fn;
}

} // namespace hyc
