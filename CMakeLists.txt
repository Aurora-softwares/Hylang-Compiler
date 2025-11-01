cmake_minimum_required(VERSION 3.20)
project(hydrogenc LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

find_package(LLVM REQUIRED)
include(LLVMConfig)

message(STATUS "Using LLVM ${LLVM_PACKAGE_VERSION}")

include_directories(${LLVM_INCLUDE_DIRS})
add_definitions(${LLVM_DEFINITIONS})

set(SOURCES
    src/main.cpp
    src/diag.cpp
    src/lexer.cpp
    src/tokens.cpp
    src/parser.cpp
    src/sema.cpp
    src/codegen.cpp
    src/winrt.cpp
    src/object_emit.cpp
    src/linker.cpp
    src/util.cpp
)

add_executable(hydrogenc ${SOURCES})

target_include_directories(hydrogenc PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

llvm_map_components_to_libnames(LLVM_LIBS
    core
    support
    target
    mc
    mcparser
    x86codegen
    x86asmparser
    x86desc
    x86disassembler
    x86asmprinter
    x86info
)

target_link_libraries(hydrogenc PRIVATE ${LLVM_LIBS})

if(MSVC)
    target_compile_options(hydrogenc PRIVATE /W4 /permissive- /EHsc)
else()
    target_compile_options(hydrogenc PRIVATE -Wall -Wextra -Wpedantic)
endif()

enable_testing()
add_test(NAME HydrogenC.Test
         COMMAND ${CMAKE_COMMAND}
                 -Dhydrogenc_exe=$<TARGET_FILE:hydrogenc>
                 -Dtest_source=${CMAKE_CURRENT_SOURCE_DIR}/tests/Test.hy
                 -Dtest_binary_dir=${CMAKE_CURRENT_BINARY_DIR}/tests
                 -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/CTest.cmake)
