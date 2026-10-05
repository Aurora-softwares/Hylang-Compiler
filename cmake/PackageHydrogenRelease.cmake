if (NOT DEFINED SOURCE_DIR OR SOURCE_DIR STREQUAL "")
    get_filename_component(SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
endif()

if (NOT DEFINED INPUT_BINARY OR INPUT_BINARY STREQUAL "")
    set(INPUT_BINARY "${SOURCE_DIR}/safe/hy")
endif()

if (NOT DEFINED VERSION OR VERSION STREQUAL "")
    message(FATAL_ERROR "Set VERSION, for example -DVERSION=alpha-0.0.1.")
endif()

if (NOT VERSION MATCHES "^[A-Za-z0-9][A-Za-z0-9._-]*$")
    message(FATAL_ERROR "VERSION may contain only letters, numbers, '.', '_', and '-'.")
endif()

get_filename_component(INPUT_BINARY "${INPUT_BINARY}" ABSOLUTE)
if (NOT EXISTS "${INPUT_BINARY}")
    message(FATAL_ERROR "Release binary was not found: ${INPUT_BINARY}")
endif()

if (IS_DIRECTORY "${INPUT_BINARY}")
    message(FATAL_ERROR "Release binary is a directory: ${INPUT_BINARY}")
endif()

if (NOT DEFINED RELEASES_DIR OR RELEASES_DIR STREQUAL "")
    set(RELEASES_DIR "${SOURCE_DIR}/releases")
endif()
get_filename_component(RELEASES_DIR "${RELEASES_DIR}" ABSOLUTE)

set(PACKAGE_NAME "hydrogen-${VERSION}-linux-x86_64")
set(ARCHIVE_NAME "${PACKAGE_NAME}.tar.gz")
set(ARCHIVE_PATH "${RELEASES_DIR}/${ARCHIVE_NAME}")
set(ARCHIVE_SUM_PATH "${ARCHIVE_PATH}.sha256")
set(STAGING_ROOT "${RELEASES_DIR}/.staging-${PACKAGE_NAME}")
set(PACKAGE_DIR "${STAGING_ROOT}/${PACKAGE_NAME}")

if ((EXISTS "${ARCHIVE_PATH}" OR EXISTS "${ARCHIVE_SUM_PATH}") AND NOT FORCE)
    message(FATAL_ERROR
        "Release output already exists. Choose a new VERSION or pass -DFORCE=ON: ${ARCHIVE_PATH}")
endif()

file(MAKE_DIRECTORY "${RELEASES_DIR}")
file(REMOVE_RECURSE "${STAGING_ROOT}")
file(MAKE_DIRECTORY "${PACKAGE_DIR}/bin")

configure_file("${INPUT_BINARY}" "${PACKAGE_DIR}/bin/hy" COPYONLY)
file(CHMOD "${PACKAGE_DIR}/bin/hy"
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
configure_file("${SOURCE_DIR}/release/README.md" "${PACKAGE_DIR}/README.md" COPYONLY)

if (EXISTS "${SOURCE_DIR}/LICENSE")
    configure_file("${SOURCE_DIR}/LICENSE" "${PACKAGE_DIR}/LICENSE" COPYONLY)
else()
    message(WARNING "No LICENSE file found; add one before publishing the release.")
endif()

file(SHA256 "${PACKAGE_DIR}/bin/hy" BINARY_SHA256)
file(WRITE "${PACKAGE_DIR}/SHA256SUMS" "${BINARY_SHA256}  bin/hy\n")
file(WRITE "${PACKAGE_DIR}/BUILD-INFO.txt"
    "Hydrogen release: ${VERSION}\n"
    "Platform: linux-x86_64\n"
    "Entrypoint: bin/hy\n")

file(REMOVE "${ARCHIVE_PATH}" "${ARCHIVE_SUM_PATH}")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar "cfvz" "${ARCHIVE_PATH}" "--format=gnutar" "${PACKAGE_NAME}"
    WORKING_DIRECTORY "${STAGING_ROOT}"
    RESULT_VARIABLE TAR_RESULT)
if (NOT TAR_RESULT EQUAL 0)
    message(FATAL_ERROR "Failed to create release archive: ${ARCHIVE_PATH}")
endif()

file(SHA256 "${ARCHIVE_PATH}" ARCHIVE_SHA256)
file(WRITE "${ARCHIVE_SUM_PATH}" "${ARCHIVE_SHA256}  ${ARCHIVE_NAME}\n")
file(REMOVE_RECURSE "${STAGING_ROOT}")

message(STATUS "Packaged Hydrogen release: ${ARCHIVE_PATH}")
message(STATUS "Archive checksum: ${ARCHIVE_SUM_PATH}")
