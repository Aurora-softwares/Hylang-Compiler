if(NOT DEFINED HY_BINARY)
    message(FATAL_ERROR "HY_BINARY is required")
endif()

if(NOT DEFINED SOURCE_WORKSPACE)
    message(FATAL_ERROR "SOURCE_WORKSPACE is required")
endif()

if(NOT DEFINED TEMP_DIR)
    message(FATAL_ERROR "TEMP_DIR is required")
endif()

file(REMOVE_RECURSE "${TEMP_DIR}")
file(MAKE_DIRECTORY "${TEMP_DIR}")
file(COPY "${SOURCE_WORKSPACE}/" DESTINATION "${TEMP_DIR}/sdk_demo")

set(WORKSPACE "${TEMP_DIR}/sdk_demo/SdkDemo.hyproj")
set(REGISTRY "${TEMP_DIR}/registry")
set(CONSUMER "${TEMP_DIR}/sdk_demo/SdkDemo.Consumer/SdkDemo.Consumer.hyproj")
set(CORE "${TEMP_DIR}/sdk_demo/SdkDemo.Core/SdkDemo.Core.hyproj")

execute_process(COMMAND "${HY_BINARY}" build "${WORKSPACE}" RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "sdk demo build failed:\n${out}\n${err}")
endif()

execute_process(COMMAND "${HY_BINARY}" test "${WORKSPACE}" RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "sdk demo test failed:\n${out}\n${err}")
endif()

execute_process(COMMAND "${HY_BINARY}" fmt --check "${TEMP_DIR}/sdk_demo" RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "sdk demo fmt check failed:\n${out}\n${err}")
endif()

execute_process(COMMAND "${HY_BINARY}" check "${WORKSPACE}" --json RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "sdk demo check failed:\n${out}\n${err}")
endif()

execute_process(COMMAND "${HY_BINARY}" package init-registry "${REGISTRY}" RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT result EQUAL 0 OR NOT EXISTS "${REGISTRY}/index.json")
    message(FATAL_ERROR "registry init failed:\n${out}\n${err}")
endif()

execute_process(COMMAND "${HY_BINARY}" package publish "${CORE}" --registry "${REGISTRY}" RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "registry publish failed:\n${out}\n${err}")
endif()

file(READ "${CONSUMER}" CONSUMER_MANIFEST)
string(REPLACE "project_references = [\"../SdkDemo.Core/SdkDemo.Core.hyproj\"]" "project_references = []" CONSUMER_MANIFEST "${CONSUMER_MANIFEST}")
file(WRITE "${CONSUMER}" "${CONSUMER_MANIFEST}")

execute_process(COMMAND "${HY_BINARY}" package search SdkDemo --registry "${REGISTRY}" RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT result EQUAL 0 OR NOT out MATCHES "SdkDemo.Core 0.1.0")
    message(FATAL_ERROR "registry search failed:\n${out}\n${err}")
endif()

execute_process(COMMAND "${HY_BINARY}" package install "${CONSUMER}" SdkDemo.Core --registry "${REGISTRY}" RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT result EQUAL 0 OR NOT out MATCHES "SdkDemo.Core 0.1.0")
    message(FATAL_ERROR "registry install failed:\n${out}\n${err}")
endif()

execute_process(COMMAND "${HY_BINARY}" run "${CONSUMER}" RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(NOT result EQUAL 0 OR NOT out MATCHES "SdkDemo.Core" OR NOT out MATCHES "bytes=8")
    message(FATAL_ERROR "consumer run failed:\n${out}\n${err}")
endif()

execute_process(COMMAND "${HY_BINARY}" package publish "${CORE}" --registry "${REGISTRY}" RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err)
if(result EQUAL 0 OR NOT err MATCHES "package already exists")
    message(FATAL_ERROR "duplicate publish should fail:\n${out}\n${err}")
endif()
