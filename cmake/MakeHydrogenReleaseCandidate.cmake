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

set(LINUX_NAME "hydrogen-${VERSION}-linux-x86_64")
set(WINDOWS_NAME "hydrogen-${VERSION}-windows-x86_64")
foreach(OUTPUT
    "${RELEASES_DIR}/${LINUX_NAME}.tar.gz"
    "${RELEASES_DIR}/${LINUX_NAME}.tar.gz.sha256"
    "${RELEASES_DIR}/${WINDOWS_NAME}.zip"
    "${RELEASES_DIR}/${WINDOWS_NAME}.zip.sha256")
    if(EXISTS "${OUTPUT}" AND NOT FORCE)
        message(FATAL_ERROR "Release output already exists. Choose a new VERSION or pass -DFORCE=ON: ${OUTPUT}")
    endif()
endforeach()

set(PROJECT "${SOURCE_DIR}/samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj")
if(NOT EXISTS "${PROJECT}")
    message(FATAL_ERROR "Linux compiler project was not found: ${PROJECT}")
endif()
set(STAGE_DIR "${RELEASES_DIR}/.candidate-hydrogen-${VERSION}")
set(BUILD_DIR "${STAGE_DIR}/build")
set(STAGE_OUTPUT "${STAGE_DIR}/output")
set(LINUX_BINARY "${BUILD_DIR}/hy-core")
file(MAKE_DIRECTORY "${RELEASES_DIR}")
file(REMOVE_RECURSE "${STAGE_DIR}")
file(MAKE_DIRECTORY "${BUILD_DIR}" "${STAGE_OUTPUT}")

execute_process(
    COMMAND "${HOST_COMPILER}" build "${PROJECT}" -o "${LINUX_BINARY}"
        --hide-progress --hide-spinner --hide-log
    RESULT_VARIABLE BUILD_RESULT
    OUTPUT_VARIABLE BUILD_OUTPUT
    ERROR_VARIABLE BUILD_ERROR)
if(NOT BUILD_RESULT STREQUAL "0" OR NOT EXISTS "${LINUX_BINARY}")
    message(FATAL_ERROR
        "Could not build the Linux compiler with ${HOST_COMPILER}\n${BUILD_OUTPUT}\n${BUILD_ERROR}")
endif()
file(READ "${LINUX_BINARY}" MAGIC LIMIT 4 HEX)
if(NOT MAGIC STREQUAL "7f454c46")
    message(FATAL_ERROR "Built Linux compiler has no ELF header: ${LINUX_BINARY}")
endif()

execute_process(
    COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE_DIR=${SOURCE_DIR}"
        "-DINPUT_BINARY=${LINUX_BINARY}"
        "-DVERSION=${VERSION}"
        "-DRELEASES_DIR=${STAGE_OUTPUT}"
        "-DFORCE=${FORCE}"
        -P "${SOURCE_DIR}/cmake/PackageHydrogenRelease.cmake"
    RESULT_VARIABLE LINUX_PACKAGE_RESULT
    OUTPUT_VARIABLE LINUX_PACKAGE_OUTPUT
    ERROR_VARIABLE LINUX_PACKAGE_ERROR)
if(NOT LINUX_PACKAGE_RESULT STREQUAL "0")
    message(FATAL_ERROR
        "Could not package Linux release\n${LINUX_PACKAGE_OUTPUT}\n${LINUX_PACKAGE_ERROR}")
endif()

execute_process(
    COMMAND "${CMAKE_COMMAND}"
        "-DSOURCE_DIR=${SOURCE_DIR}"
        "-DHOST_COMPILER=${HOST_COMPILER}"
        "-DVERSION=${VERSION}"
        "-DRELEASES_DIR=${STAGE_OUTPUT}"
        "-DFORCE=${FORCE}"
        -P "${SOURCE_DIR}/cmake/MakeHydrogenWindowsRelease.cmake"
    RESULT_VARIABLE WINDOWS_PACKAGE_RESULT
    OUTPUT_VARIABLE WINDOWS_PACKAGE_OUTPUT
    ERROR_VARIABLE WINDOWS_PACKAGE_ERROR)
if(NOT WINDOWS_PACKAGE_RESULT STREQUAL "0")
    message(FATAL_ERROR
        "Could not build/package Windows release\n${WINDOWS_PACKAGE_OUTPUT}\n${WINDOWS_PACKAGE_ERROR}")
endif()

foreach(NAME "${LINUX_NAME}.tar.gz" "${WINDOWS_NAME}.zip")
    set(ARCHIVE "${STAGE_OUTPUT}/${NAME}")
    file(SHA256 "${ARCHIVE}" DIGEST)
    file(READ "${ARCHIVE}.sha256" SIDECAR)
    if(NOT SIDECAR STREQUAL "${DIGEST}  ${NAME}\n")
        message(FATAL_ERROR "Release checksum does not match ${ARCHIVE}")
    endif()
endforeach()
if(FORCE)
    file(REMOVE
        "${RELEASES_DIR}/${LINUX_NAME}.tar.gz"
        "${RELEASES_DIR}/${LINUX_NAME}.tar.gz.sha256"
        "${RELEASES_DIR}/${WINDOWS_NAME}.zip"
        "${RELEASES_DIR}/${WINDOWS_NAME}.zip.sha256")
endif()
foreach(NAME
    "${LINUX_NAME}.tar.gz" "${LINUX_NAME}.tar.gz.sha256"
    "${WINDOWS_NAME}.zip" "${WINDOWS_NAME}.zip.sha256")
    file(RENAME "${STAGE_OUTPUT}/${NAME}" "${RELEASES_DIR}/${NAME}")
endforeach()
file(REMOVE_RECURSE "${STAGE_DIR}")
message(STATUS "Release candidate built for Linux x86-64 and Windows x64 in ${RELEASES_DIR}")
message(STATUS "Australis compiler package skipped: no supported self-hosted Australis CLI target")
