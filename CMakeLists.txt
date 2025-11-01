cmake_minimum_required(VERSION 3.20)
project(HydrogenC LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_MODULE_PATH "${CMAKE_MODULE_PATH};${CMAKE_CURRENT_SOURCE_DIR}/cmake")

find_package(LLVM REQUIRED)

message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")

include_directories(${LLVM_INCLUDE_DIRS})
add_definitions(${LLVM_DEFINITIONS})

llvm_map_components_to_libnames(LLVM_LIBS
  Core
  IRReader
  MC
  MCParser
  Option
  OrcJIT
  Support
  Target
  X86AsmParser
  X86AsmPrinter
  X86Desc
  X86Info)

add_executable(hydrogenc
  src/main.cpp
  src/diag.cpp
  src/lexer.cpp
  src/parser.cpp
  src/sema.cpp
  src/codegen.cpp
  src/winrt.cpp
  src/object_emit.cpp
  src/linker.cpp
  src/util.cpp)

target_include_directories(hydrogenc PRIVATE src)

target_link_libraries(hydrogenc PRIVATE ${LLVM_LIBS})

if (MSVC)
  target_compile_options(hydrogenc PRIVATE /permissive- /Zc:__cplusplus /EHsc /MP)
endif()

include(CTest)
if (BUILD_TESTING)
  add_test(NAME hydrogenc_test
    COMMAND ${CMAKE_COMMAND}
      -Dhydrogenc=$<TARGET_FILE:hydrogenc>
      -Dsource=${CMAKE_CURRENT_SOURCE_DIR}/tests/Test.hy
      -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/CTest.cmake)
endif()
