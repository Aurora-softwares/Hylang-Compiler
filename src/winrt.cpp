#include "winrt.hpp"

#include <llvm/IR/Constants.h>
#include <llvm/IR/Function.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/Type.h>

namespace winrt {
namespace {
llvm::Function *declareFunction(llvm::Module &module, const std::string &name, llvm::FunctionType *type) {
    if (auto *fn = module.getFunction(name)) {
        return fn;
    }
    return llvm::Function::Create(type, llvm::Function::ExternalLinkage, name, module);
}
}

llvm::Function *getStdHandleDecl(llvm::Module &module) {
    auto &ctx = module.getContext();
    auto *i32Ty = llvm::Type::getInt32Ty(ctx);
    auto *i8PtrTy = llvm::Type::getInt8PtrTy(ctx);
    auto *fnTy = llvm::FunctionType::get(i8PtrTy, {i32Ty}, false);
    return declareFunction(module, "GetStdHandle", fnTy);
}

llvm::Function *getWriteFileDecl(llvm::Module &module) {
    auto &ctx = module.getContext();
    auto *i32Ty = llvm::Type::getInt32Ty(ctx);
    auto *i8PtrTy = llvm::Type::getInt8PtrTy(ctx);
    auto *ptrI32Ty = llvm::PointerType::getUnqual(i32Ty);
    auto *fnTy = llvm::FunctionType::get(llvm::Type::getInt1Ty(ctx), {i8PtrTy, i8PtrTy, i32Ty, ptrI32Ty, i8PtrTy}, false);
    return declareFunction(module, "WriteFile", fnTy);
}

llvm::Function *getOrCreatePrintFunction(llvm::Module &module) {
    if (auto *fn = module.getFunction("hy_print_i32")) {
        return fn;
    }

    auto &ctx = module.getContext();
    llvm::IRBuilder<> builder(ctx);
    auto *voidTy = llvm::Type::getVoidTy(ctx);
    auto *i32Ty = llvm::Type::getInt32Ty(ctx);
    auto *i64Ty = llvm::Type::getInt64Ty(ctx);
    auto *i8Ty = llvm::Type::getInt8Ty(ctx);
    auto *i1Ty = llvm::Type::getInt1Ty(ctx);

    auto *fnTy = llvm::FunctionType::get(voidTy, {i32Ty}, false);
    auto *fn = llvm::Function::Create(fnTy, llvm::Function::ExternalLinkage, "hy_print_i32", module);
    fn->getArg(0)->setName("value");

    auto *arrayTy = llvm::ArrayType::get(i8Ty, 32);
    auto *entry = llvm::BasicBlock::Create(ctx, "entry", fn);
    auto *signBlock = llvm::BasicBlock::Create(ctx, "sign", fn);
    auto *afterSign = llvm::BasicBlock::Create(ctx, "after_sign", fn);
    auto *zeroBlock = llvm::BasicBlock::Create(ctx, "zero", fn);
    auto *nonZeroBlock = llvm::BasicBlock::Create(ctx, "non_zero", fn);
    auto *loopCheck = llvm::BasicBlock::Create(ctx, "loop_check", fn);
    auto *loopBody = llvm::BasicBlock::Create(ctx, "loop_body", fn);
    auto *digitsDone = llvm::BasicBlock::Create(ctx, "digits_done", fn);
    auto *negBlock = llvm::BasicBlock::Create(ctx, "neg", fn);
    auto *afterNeg = llvm::BasicBlock::Create(ctx, "after_neg", fn);
    auto *exitBlock = llvm::BasicBlock::Create(ctx, "exit", fn);

    builder.SetInsertPoint(entry);
    auto *bufAlloca = builder.CreateAlloca(arrayTy, nullptr, "buf");
    auto *idxAlloca = builder.CreateAlloca(i32Ty, nullptr, "idx");
    auto *tempAlloca = builder.CreateAlloca(i64Ty, nullptr, "temp");
    auto *negAlloca = builder.CreateAlloca(i1Ty, nullptr, "neg");

    auto *newlineIdx = llvm::ConstantInt::get(i32Ty, 31);
    auto *zero64 = llvm::ConstantInt::get(i64Ty, 0);
    auto *newlineIdx64 = llvm::ConstantInt::get(i64Ty, 31);
    auto *newlinePos = builder.CreateInBoundsGEP(arrayTy, bufAlloca,
                                                 {zero64, newlineIdx64},
                                                 "newline_pos");
    builder.CreateStore(llvm::ConstantInt::get(i8Ty, '\n'), newlinePos);
    builder.CreateStore(llvm::ConstantInt::get(i32Ty, 30), idxAlloca);
    auto *value64 = builder.CreateSExt(fn->getArg(0), i64Ty, "value64");
    builder.CreateStore(value64, tempAlloca);
    builder.CreateStore(llvm::ConstantInt::getFalse(ctx), negAlloca);

    auto *isNeg = builder.CreateICmpSLT(fn->getArg(0), llvm::ConstantInt::get(i32Ty, 0));
    builder.CreateCondBr(isNeg, signBlock, afterSign);

    builder.SetInsertPoint(signBlock);
    auto *loadedVal = builder.CreateLoad(i64Ty, tempAlloca, "loaded");
    auto *negVal = builder.CreateNeg(loadedVal);
    builder.CreateStore(negVal, tempAlloca);
    builder.CreateStore(llvm::ConstantInt::getTrue(ctx), negAlloca);
    builder.CreateBr(afterSign);

    builder.SetInsertPoint(afterSign);
    auto *tempVal = builder.CreateLoad(i64Ty, tempAlloca, "tempval");
    auto *isZero = builder.CreateICmpEQ(tempVal, llvm::ConstantInt::get(i64Ty, 0));
    builder.CreateCondBr(isZero, zeroBlock, nonZeroBlock);

    builder.SetInsertPoint(zeroBlock);
    auto *idxZero = builder.CreateLoad(i32Ty, idxAlloca, "idx_zero");
    auto *idxZero64 = builder.CreateSExt(idxZero, i64Ty);
    auto *posZero = builder.CreateInBoundsGEP(arrayTy, bufAlloca,
                                              {llvm::ConstantInt::get(i64Ty, 0), idxZero64}, "pos_zero");
    builder.CreateStore(llvm::ConstantInt::get(i8Ty, '0'), posZero);
    auto *idxZeroNext = builder.CreateSub(idxZero, llvm::ConstantInt::get(i32Ty, 1));
    builder.CreateStore(idxZeroNext, idxAlloca);
    builder.CreateBr(digitsDone);

    builder.SetInsertPoint(nonZeroBlock);
    builder.CreateBr(loopCheck);

    builder.SetInsertPoint(loopCheck);
    auto *loopVal = builder.CreateLoad(i64Ty, tempAlloca, "loop_val");
    auto *loopCond = builder.CreateICmpEQ(loopVal, llvm::ConstantInt::get(i64Ty, 0));
    builder.CreateCondBr(loopCond, digitsDone, loopBody);

    builder.SetInsertPoint(loopBody);
    auto *currentVal = builder.CreateLoad(i64Ty, tempAlloca, "current");
    auto *divVal = builder.CreateSDiv(currentVal, llvm::ConstantInt::get(i64Ty, 10));
    auto *remVal = builder.CreateSRem(currentVal, llvm::ConstantInt::get(i64Ty, 10));
    builder.CreateStore(divVal, tempAlloca);
    auto *idxLoop = builder.CreateLoad(i32Ty, idxAlloca, "idx_loop");
    auto *idxLoop64 = builder.CreateSExt(idxLoop, i64Ty);
    auto *posLoop = builder.CreateInBoundsGEP(arrayTy, bufAlloca,
                                              {llvm::ConstantInt::get(i64Ty, 0), idxLoop64}, "pos_loop");
    auto *digitInt = builder.CreateTrunc(remVal, i32Ty, "digit32");
    auto *digitChar = builder.CreateAdd(digitInt, llvm::ConstantInt::get(i32Ty, '0'));
    auto *digitTrunc = builder.CreateTrunc(digitChar, i8Ty);
    builder.CreateStore(digitTrunc, posLoop);
    auto *idxNext = builder.CreateSub(idxLoop, llvm::ConstantInt::get(i32Ty, 1));
    builder.CreateStore(idxNext, idxAlloca);
    builder.CreateBr(loopCheck);

    builder.SetInsertPoint(digitsDone);
    auto *isNegVal = builder.CreateLoad(i1Ty, negAlloca, "isneg");
    builder.CreateCondBr(isNegVal, negBlock, afterNeg);

    builder.SetInsertPoint(negBlock);
    auto *idxNeg = builder.CreateLoad(i32Ty, idxAlloca, "idx_neg");
    auto *idxNeg64 = builder.CreateSExt(idxNeg, i64Ty);
    auto *posNeg = builder.CreateInBoundsGEP(arrayTy, bufAlloca,
                                             {llvm::ConstantInt::get(i64Ty, 0), idxNeg64}, "pos_neg");
    builder.CreateStore(llvm::ConstantInt::get(i8Ty, '-'), posNeg);
    auto *idxNegNext = builder.CreateSub(idxNeg, llvm::ConstantInt::get(i32Ty, 1));
    builder.CreateStore(idxNegNext, idxAlloca);
    builder.CreateBr(afterNeg);

    builder.SetInsertPoint(afterNeg);
    auto *idxFinal = builder.CreateLoad(i32Ty, idxAlloca, "idx_final");
    auto *startIndex = builder.CreateAdd(idxFinal, llvm::ConstantInt::get(i32Ty, 1), "start_index");
    auto *startIndex64 = builder.CreateSExt(startIndex, i64Ty);
    auto *startPtr = builder.CreateInBoundsGEP(arrayTy, bufAlloca,
                                               {llvm::ConstantInt::get(i64Ty, 0), startIndex64}, "start_ptr");
    auto *lenDiff = builder.CreateSub(newlineIdx, startIndex, "len_diff");
    auto *length = builder.CreateAdd(lenDiff, llvm::ConstantInt::get(i32Ty, 1), "length");

    auto *stdoutHandle = getStdHandleDecl(module);
    auto *writeFile = getWriteFileDecl(module);
    auto *handle = builder.CreateCall(stdoutHandle, {llvm::ConstantInt::get(i32Ty, -11)});
    auto *bytesAlloca = builder.CreateAlloca(i32Ty, nullptr, "bytes_written");
    builder.CreateStore(llvm::ConstantInt::get(i32Ty, 0), bytesAlloca);
    auto *startPtrCast = builder.CreatePointerCast(startPtr, llvm::Type::getInt8PtrTy(ctx));
    auto *nullPtr = llvm::ConstantPointerNull::get(llvm::Type::getInt8PtrTy(ctx));
    builder.CreateCall(writeFile, {handle, startPtrCast, length, bytesAlloca, nullPtr});
    builder.CreateBr(exitBlock);

    builder.SetInsertPoint(exitBlock);
    builder.CreateRetVoid();

    return fn;
}

} // namespace winrt
