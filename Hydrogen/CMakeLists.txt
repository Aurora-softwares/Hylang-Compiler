cmake_minimum_required(VERSION 3.15)
project(Hydrogen LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(LLVM REQUIRED CONFIG)
message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")

include_directories(${LLVM_INCLUDE_DIRS})
add_definitions(${LLVM_DEFINITIONS})

llvm_map_components_to_libnames(LLVM_LIBS
    core
    native
    nativecodegen
    orcjit
    mcjit
    passes
    support
)

set(SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src)
set(SOURCES
    ${SRC_DIR}/main.cpp
    ${SRC_DIR}/CLI.cpp
    ${SRC_DIR}/Error.cpp
    ${SRC_DIR}/Lexer.cpp
    ${SRC_DIR}/Parser.cpp
    ${SRC_DIR}/Codegen.cpp
)

add_executable(hyc ${SOURCES})

target_include_directories(hyc PRIVATE ${SRC_DIR})

target_link_libraries(hyc PRIVATE ${LLVM_LIBS} lldCommon lldELF)

target_compile_definitions(hyc PRIVATE HY_VERSION="0.1.0")
