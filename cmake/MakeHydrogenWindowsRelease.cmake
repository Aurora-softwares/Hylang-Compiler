if(NOT DEFINED SOURCE_DIR OR SOURCE_DIR STREQUAL "")
    get_filename_component(SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
endif()
get_filename_component(SOURCE_DIR "${SOURCE_DIR}" ABSOLUTE)

if(NOT DEFINED HOST_COMPILER OR HOST_COMPILER STREQUAL "")
    set(HOST_COMPILER "${SOURCE_DIR}/safe/hy")
endif()
get_filename_component(HOST_COMPILER "${HOST_COMPILER}" ABSOLUTE)
if(NOT EXISTS "${HOST_COMPILER}" OR IS_DIRECTORY "${HOST_COMPILER}")
    message(FATAL_ERROR "A verified self-hosted HOST_COMPILER is required: ${HOST_COMPILER}")
endif()

if(NOT DEFINED VERSION OR VERSION STREQUAL "")
    message(FATAL_ERROR "Set VERSION, for example -DVERSION=alpha-0.0.3.")
endif()
if(NOT VERSION MATCHES "^[A-Za-z0-9][A-Za-z0-9._-]*$")
    message(FATAL_ERROR "Invalid release version: ${VERSION}")
endif()

if(NOT DEFINED RELEASES_DIR OR RELEASES_DIR STREQUAL "")
    set(RELEASES_DIR "${SOURCE_DIR}/releases")
endif()
get_filename_component(RELEASES_DIR "${RELEASES_DIR}" ABSOLUTE)
set(PACKAGE_NAME "hydrogen-${VERSION}-windows-x86_64")
set(ARCHIVE "${RELEASES_DIR}/${PACKAGE_NAME}.zip")
if((EXISTS "${ARCHIVE}" OR EXISTS "${ARCHIVE}.sha256") AND NOT FORCE)
    message(FATAL_ERROR "Release output already exists. Choose a new VERSION or pass -DFORCE=ON: ${ARCHIVE}")
endif()

set(PROJECT "${SOURCE_DIR}/src/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.Windows.hyproj")
if(NOT EXISTS "${PROJECT}")
    message(FATAL_ERROR "Windows compiler project was not found: ${PROJECT}")
endif()
set(BUILD_DIR "${RELEASES_DIR}/.build-${PACKAGE_NAME}")
set(WINDOWS_BINARY "${BUILD_DIR}/hy-core.exe")
file(MAKE_DIRECTORY "${RELEASES_DIR}")
file(REMOVE_RECURSE "${BUILD_DIR}")
file(MAKE_DIRECTORY "${BUILD_DIR}")

execute_process(
    COMMAND "${HOST_COMPILER}" build "${PROJECT}" -o "${WINDOWS_BINARY}"
        --hide-progress --hide-spinner --hide-log
    RESULT_VARIABLE BUILD_RESULT
    OUTPUT_VARIABLE BUILD_OUTPUT
    ERROR_VARIABLE BUILD_ERROR)
if(NOT BUILD_RESULT STREQUAL "0" OR NOT EXISTS "${WINDOWS_BINARY}")
    message(FATAL_ERROR
        "Could not build the Windows compiler with ${HOST_COMPILER}\n${BUILD_OUTPUT}\n${BUILD_ERROR}")
endif()
file(READ "${WINDOWS_BINARY}" MAGIC LIMIT 2 HEX)
if(NOT MAGIC STREQUAL "4d5a")
    message(FATAL_ERROR "Built Windows compiler has no MZ header: ${WINDOWS_BINARY}")
endif()

execute_process(
    COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE_DIR=${SOURCE_DIR}"
        "-DINPUT_BINARY=${WINDOWS_BINARY}"
        "-DVERSION=${VERSION}"
        "-DRELEASES_DIR=${RELEASES_DIR}"
        "-DFORCE=${FORCE}"
        -P "${SOURCE_DIR}/cmake/PackageHydrogenWindowsRelease.cmake"
    RESULT_VARIABLE PACKAGE_RESULT
    OUTPUT_VARIABLE PACKAGE_OUTPUT
    ERROR_VARIABLE PACKAGE_ERROR)
if(NOT PACKAGE_RESULT STREQUAL "0")
    message(FATAL_ERROR "Could not package Windows release\n${PACKAGE_OUTPUT}\n${PACKAGE_ERROR}")
endif()

file(SHA256 "${ARCHIVE}" ARCHIVE_SHA256)
file(READ "${ARCHIVE}.sha256" SIDECAR)
if(NOT SIDECAR STREQUAL "${ARCHIVE_SHA256}  ${PACKAGE_NAME}.zip\n")
    message(FATAL_ERROR "Windows release sidecar does not match the archive")
endif()
file(REMOVE_RECURSE "${BUILD_DIR}")
message(STATUS "Built and packaged Windows compiler: ${ARCHIVE}")
message(STATUS "Archive checksum: ${ARCHIVE}.sha256")
