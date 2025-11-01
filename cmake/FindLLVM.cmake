if(NOT LLVM_DIR AND DEFINED ENV{LLVM_DIR})
    set(LLVM_DIR "$ENV{LLVM_DIR}")
endif()

if(NOT LLVM_DIR AND DEFINED ENV{LLVM_ROOT})
    set(LLVM_DIR "$ENV{LLVM_ROOT}/lib/cmake/llvm")
endif()

if(NOT LLVM_DIR)
    message(FATAL_ERROR "LLVM_DIR is not set. Set LLVM_DIR or the LLVM_DIR environment variable to the LLVM cmake directory.")
endif()

if(NOT EXISTS "${LLVM_DIR}/LLVMConfig.cmake")
    message(FATAL_ERROR "LLVMConfig.cmake not found in ${LLVM_DIR}")
endif()

include("${LLVM_DIR}/LLVMConfig.cmake")
set(LLVM_FOUND TRUE)
