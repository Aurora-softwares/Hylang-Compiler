if(NOT DEFINED HY_BINARY)
    message(FATAL_ERROR "HY_BINARY is required")
endif()

if(NOT DEFINED INPUT_FILE)
    message(FATAL_ERROR "INPUT_FILE is required")
endif()

if(NOT DEFINED TEMP_DIR)
    message(FATAL_ERROR "TEMP_DIR is required")
endif()

file(MAKE_DIRECTORY "${TEMP_DIR}")
set(URI "file://${INPUT_FILE}")
set(MSG1 "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}")
set(MSG2 "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/documentSymbol\",\"params\":{\"textDocument\":{\"uri\":\"${URI}\"}}}")
set(MSG3 "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"${URI}\"},\"position\":{\"line\":1,\"character\":24}}}")
set(MSG4 "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\",\"params\":null}")
set(MSG5 "{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":null}")

set(INPUT "")
foreach(MSG IN ITEMS MSG1 MSG2 MSG3 MSG4 MSG5)
    string(LENGTH "${${MSG}}" LEN)
    string(APPEND INPUT "Content-Length: ${LEN}\r\n\r\n${${MSG}}")
endforeach()

set(INPUT_PATH "${TEMP_DIR}/lsp-input.txt")
file(WRITE "${INPUT_PATH}" "${INPUT}")

execute_process(
    COMMAND "${HY_BINARY}" lsp
    INPUT_FILE "${INPUT_PATH}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE out
    ERROR_VARIABLE err
)

if(NOT result EQUAL 0)
    message(FATAL_ERROR "hy lsp failed:\n${out}\n${err}")
endif()

if(NOT out MATCHES "documentSymbolProvider" OR NOT out MATCHES "Report" OR NOT out MATCHES "hoverProvider")
    message(FATAL_ERROR "hy lsp response missing expected data:\n${out}\n${err}")
endif()
