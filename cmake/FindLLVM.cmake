# Helper to locate LLVM via LLVM_DIR or environment variables.
if(NOT LLVM_DIR)
    if(DEFINED ENV{LLVM_DIR})
        set(LLVM_DIR "$ENV{LLVM_DIR}" CACHE PATH "Path to LLVMConfig.cmake" FORCE)
    elseif(DEFINED ENV{LLVM_ROOT})
        set(LLVM_DIR "$ENV{LLVM_ROOT}/lib/cmake/llvm" CACHE PATH "Path to LLVMConfig.cmake" FORCE)
    endif()
endif()

find_package(LLVM REQUIRED CONFIG)
