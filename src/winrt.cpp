#include "winrt.hpp"

#include <llvm/IR/BasicBlock.h>
#include <llvm/IR/Constants.h>
#include <llvm/IR/Function.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/Type.h>

namespace hyc {

WinRuntime::WinRuntime(llvm::Module &module) : m_module(module) {}

llvm::Function *WinRuntime::getPrintI32() {
    if (!m_printI32) {
        m_printI32 = createPrintI32();
    }
    return m_printI32;
}

llvm::Function *WinRuntime::declareGetStdHandle() {
    if (m_getStdHandle) {
        return m_getStdHandle;
    }
    auto &ctx = m_module.getContext();
    auto *fnTy = llvm::FunctionType::get(llvm::Type::getInt8PtrTy(ctx), {llvm::Type::getInt32Ty(ctx)}, false);
    m_getStdHandle = llvm::Function::Create(fnTy, llvm::GlobalValue::ExternalLinkage, "GetStdHandle", m_module);
    m_getStdHandle->setDLLStorageClass(llvm::GlobalValue::DLLImportStorageClass);
    return m_getStdHandle;
}

llvm::Function *WinRuntime::declareWriteFile() {
    if (m_writeFile) {
        return m_writeFile;
    }
    auto &ctx = m_module.getContext();
    auto *i32 = llvm::Type::getInt32Ty(ctx);
    auto *i8Ptr = llvm::Type::getInt8PtrTy(ctx);
    auto *fnTy = llvm::FunctionType::get(i32, {i8Ptr, i8Ptr, i32, llvm::PointerType::getUnqual(i32), i8Ptr}, false);
    m_writeFile = llvm::Function::Create(fnTy, llvm::GlobalValue::ExternalLinkage, "WriteFile", m_module);
    m_writeFile->setDLLStorageClass(llvm::GlobalValue::DLLImportStorageClass);
    return m_writeFile;
}

llvm::Function *WinRuntime::createPrintI32() {
    auto &ctx = m_module.getContext();
    llvm::IRBuilder<> builder(ctx);

    auto *fnTy = llvm::FunctionType::get(llvm::Type::getVoidTy(ctx), {llvm::Type::getInt32Ty(ctx)}, false);
    auto *fn = llvm::Function::Create(fnTy, llvm::GlobalValue::InternalLinkage, "hy_print_i32", m_module);
    fn->setDSOLocal(true);

    auto *entry = llvm::BasicBlock::Create(ctx, "entry", fn);
    auto *zeroBlock = llvm::BasicBlock::Create(ctx, "zero", fn);
    auto *nonZeroBlock = llvm::BasicBlock::Create(ctx, "nonzero", fn);
    auto *loopBody = llvm::BasicBlock::Create(ctx, "loop.body", fn);
    auto *loopCond = llvm::BasicBlock::Create(ctx, "loop.cond", fn);
    auto *afterLoop = llvm::BasicBlock::Create(ctx, "after.loop", fn);
    auto *signBlock = llvm::BasicBlock::Create(ctx, "sign", fn);
    auto *copyInit = llvm::BasicBlock::Create(ctx, "copy.init", fn);
    auto *copyCond = llvm::BasicBlock::Create(ctx, "copy.cond", fn);
    auto *copyBody = llvm::BasicBlock::Create(ctx, "copy.body", fn);
    auto *afterDigits = llvm::BasicBlock::Create(ctx, "after", fn);

    builder.SetInsertPoint(entry);
    auto *arg = fn->getArg(0);
    arg->setName("value");

    auto *bufferTy = llvm::ArrayType::get(llvm::Type::getInt8Ty(ctx), 32);
    auto *digitsTy = llvm::ArrayType::get(llvm::Type::getInt8Ty(ctx), 32);

    auto *bufferAlloca = builder.CreateAlloca(bufferTy, nullptr, "buffer");
    auto *digitsAlloca = builder.CreateAlloca(digitsTy, nullptr, "digits");
    auto *posAlloca = builder.CreateAlloca(llvm::Type::getInt32Ty(ctx), nullptr, "pos");
    auto *dposAlloca = builder.CreateAlloca(llvm::Type::getInt32Ty(ctx), nullptr, "dpos");
    auto *valAlloca = builder.CreateAlloca(llvm::Type::getInt32Ty(ctx), nullptr, "val");
    auto *negAlloca = builder.CreateAlloca(llvm::Type::getInt1Ty(ctx), nullptr, "neg");
    auto *writtenAlloca = builder.CreateAlloca(llvm::Type::getInt32Ty(ctx), nullptr, "written");

    builder.CreateStore(llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 0), posAlloca);
    builder.CreateStore(llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 0), dposAlloca);
    auto *isNeg = builder.CreateICmpSLT(arg, llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 0));
    builder.CreateStore(isNeg, negAlloca);
    auto *negated = builder.CreateNeg(arg);
    auto *absValue = builder.CreateSelect(isNeg, negated, arg);
    builder.CreateStore(absValue, valAlloca);
    auto *isZero = builder.CreateICmpEQ(absValue, llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 0));
    builder.CreateCondBr(isZero, zeroBlock, nonZeroBlock);

    builder.SetInsertPoint(zeroBlock);
    auto *bufPtrZero = builder.CreateInBoundsGEP(bufferTy, bufferAlloca, {llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 0),
                                                                         llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 0)});
    builder.CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(ctx), '0'), bufPtrZero);
    builder.CreateStore(llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 1), posAlloca);
    builder.CreateBr(afterDigits);

    builder.SetInsertPoint(nonZeroBlock);
    builder.CreateStore(llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 0), dposAlloca);
    builder.CreateBr(loopBody);

    builder.SetInsertPoint(loopBody);
    auto *currentVal = builder.CreateLoad(llvm::Type::getInt32Ty(ctx), valAlloca);
    auto *div = builder.CreateUDiv(currentVal, llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 10));
    auto *rem = builder.CreateURem(currentVal, llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 10));
    builder.CreateStore(div, valAlloca);
    auto *dpos = builder.CreateLoad(llvm::Type::getInt32Ty(ctx), dposAlloca);
    auto *digitPtr = builder.CreateInBoundsGEP(digitsTy, digitsAlloca,
                                               {llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 0), dpos});
    auto *ascii = builder.CreateAdd(rem, llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), '0'));
    builder.CreateStore(builder.CreateTrunc(ascii, llvm::Type::getInt8Ty(ctx)), digitPtr);
    auto *dposNext = builder.CreateAdd(dpos, llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 1));
    builder.CreateStore(dposNext, dposAlloca);
    builder.CreateBr(loopCond);

    builder.SetInsertPoint(loopCond);
    auto *valNow = builder.CreateLoad(llvm::Type::getInt32Ty(ctx), valAlloca);
    auto *moreDigits = builder.CreateICmpUGT(valNow, llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 0));
    builder.CreateCondBr(moreDigits, loopBody, afterLoop);

    builder.SetInsertPoint(afterLoop);
    auto *negFlag = builder.CreateLoad(llvm::Type::getInt1Ty(ctx), negAlloca);
    builder.CreateCondBr(negFlag, signBlock, copyInit);

    builder.SetInsertPoint(signBlock);
    auto *posVal = builder.CreateLoad(llvm::Type::getInt32Ty(ctx), posAlloca);
    auto *signPtr = builder.CreateInBoundsGEP(bufferTy, bufferAlloca,
                                              {llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 0), posVal});
    builder.CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(ctx), '-'), signPtr);
    auto *posNext = builder.CreateAdd(posVal, llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 1));
    builder.CreateStore(posNext, posAlloca);
    builder.CreateBr(copyInit);

    builder.SetInsertPoint(copyInit);
    builder.CreateBr(copyCond);

    builder.SetInsertPoint(copyCond);
    auto *dposCur = builder.CreateLoad(llvm::Type::getInt32Ty(ctx), dposAlloca);
    auto *hasDigits = builder.CreateICmpSGT(dposCur, llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 0));
    builder.CreateCondBr(hasDigits, copyBody, afterDigits);

    builder.SetInsertPoint(copyBody);
    auto *dposPrev = builder.CreateLoad(llvm::Type::getInt32Ty(ctx), dposAlloca);
    auto *index = builder.CreateSub(dposPrev, llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 1));
    builder.CreateStore(index, dposAlloca);
    auto *digitSrc = builder.CreateInBoundsGEP(digitsTy, digitsAlloca,
                                               {llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 0), index});
    auto *digitVal = builder.CreateLoad(llvm::Type::getInt8Ty(ctx), digitSrc);
    auto *posCur = builder.CreateLoad(llvm::Type::getInt32Ty(ctx), posAlloca);
    auto *destPtr = builder.CreateInBoundsGEP(bufferTy, bufferAlloca,
                                              {llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 0), posCur});
    builder.CreateStore(digitVal, destPtr);
    auto *posInc = builder.CreateAdd(posCur, llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 1));
    builder.CreateStore(posInc, posAlloca);
    builder.CreateBr(copyCond);

    builder.SetInsertPoint(afterDigits);
    auto *posFinal = builder.CreateLoad(llvm::Type::getInt32Ty(ctx), posAlloca);
    auto *newlinePtr = builder.CreateInBoundsGEP(bufferTy, bufferAlloca,
                                                 {llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 0), posFinal});
    builder.CreateStore(llvm::ConstantInt::get(llvm::Type::getInt8Ty(ctx), '\n'), newlinePtr);
    auto *totalLen = builder.CreateAdd(posFinal, llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 1));
    builder.CreateStore(totalLen, posAlloca);

    auto *handle = builder.CreateCall(declareGetStdHandle(),
                                      {llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), -11, true)});
    auto *bufPtr = builder.CreateInBoundsGEP(bufferTy, bufferAlloca,
                                             {llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 0),
                                              llvm::ConstantInt::get(llvm::Type::getInt32Ty(ctx), 0)});
    builder.CreateCall(declareWriteFile(),
                       {handle, bufPtr, totalLen, writtenAlloca,
                        llvm::ConstantPointerNull::get(llvm::Type::getInt8PtrTy(ctx))});
    builder.CreateRetVoid();

    return fn;
}

} // namespace hyc
