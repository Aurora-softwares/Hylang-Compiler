cmake_minimum_required(VERSION 3.20)
project(HydrogenC LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

find_package(LLVM REQUIRED)

message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")

include_directories(${LLVM_INCLUDE_DIRS})
link_directories(${LLVM_LIBRARY_DIRS})
add_definitions(${LLVM_DEFINITIONS})

set(SOURCES
    src/main.cpp
    src/diag.cpp
    src/util.cpp
    src/tokens.cpp
    src/lexer.cpp
    src/parser.cpp
    src/sema.cpp
    src/codegen.cpp
    src/winrt.cpp
    src/object_emit.cpp
    src/linker.cpp)

add_executable(hydrogenc ${SOURCES})
target_include_directories(hydrogenc PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

llvm_map_components_to_libnames(LLVM_LIBS
    Core
    Support
    Target
    MC
    MCParser
    X86AsmParser
    X86AsmPrinter
    X86CodeGen
    X86Desc
    X86Disassembler
    X86Info)

target_link_libraries(hydrogenc PRIVATE ${LLVM_LIBS})

if (MSVC)
    target_compile_options(hydrogenc PRIVATE /W4 /EHsc)
else()
    target_compile_options(hydrogenc PRIVATE -Wall -Wextra -pedantic)
endif()

enable_testing()
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/tests")
add_test(NAME HydrogenCExample
    COMMAND ${CMAKE_COMMAND}
        -DHYC_COMPILER=$<TARGET_FILE:hydrogenc>
        -DTEST_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/tests/Test.hy
        -DTEST_BINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}/tests
        -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/CTest.cmake)
