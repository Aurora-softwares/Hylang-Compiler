cmake_minimum_required(VERSION 3.16)
project(HydrogenC VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

find_package(LLVM REQUIRED CONFIG)

message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")

include_directories(${LLVM_INCLUDE_DIRS})
add_definitions(${LLVM_DEFINITIONS})

set(SRC
    src/main.cpp
    src/util.cpp
    src/diag.cpp
    src/tokens.cpp
    src/lexer.cpp
    src/parser.cpp
    src/ast.hpp
    src/sema.cpp
    src/codegen.cpp
    src/winrt.cpp
    src/object_emit.cpp
    src/linker.cpp
)

add_executable(hydrogenc ${SRC})

set_target_properties(hydrogenc PROPERTIES
    CXX_STANDARD 20
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO
)

if(MSVC)
    target_compile_options(hydrogenc PRIVATE /EHsc /W4 /permissive- /Zc:__cplusplus)
else()
    target_compile_options(hydrogenc PRIVATE -Wall -Wextra -Wpedantic)
endif()

llvm_map_components_to_libnames(LLVM_LIBS
    Core
    IRReader
    Support
    Target
    MC
    MCParser
    Option
    X86AsmParser
    X86CodeGen
    X86AsmPrinter
    X86Desc
    X86Info
    X86Utils
    AsmPrinter
    Passes
)

target_link_libraries(hydrogenc PRIVATE ${LLVM_LIBS})

if(MSVC)
    target_compile_definitions(hydrogenc PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()

include(CTest)

if(BUILD_TESTING)
    add_test(NAME HydrogenCTest
        COMMAND ${CMAKE_COMMAND}
            -Dhydrogenc=$<TARGET_FILE:hydrogenc>
            -Dsource_dir=${CMAKE_CURRENT_SOURCE_DIR}
            -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/CTest.cmake)
endif()
