if(NOT LLVM_DIR)
  if(DEFINED ENV{LLVM_DIR})
    set(LLVM_DIR "$ENV{LLVM_DIR}" CACHE PATH "Path to LLVMConfig.cmake")
  endif()
endif()

find_package(LLVM CONFIG)

if(NOT LLVM_FOUND)
  message(FATAL_ERROR "LLVM not found. Set LLVM_DIR to the LLVM CMake configuration directory.")
endif()
