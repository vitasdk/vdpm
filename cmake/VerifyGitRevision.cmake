if(NOT DEFINED SOURCE_DIR)
    message(FATAL_ERROR "SOURCE_DIR is required")
endif()

if(NOT DEFINED EXPECTED_REVISION)
    message(FATAL_ERROR "EXPECTED_REVISION is required")
endif()

find_package(Git REQUIRED)
execute_process(
    COMMAND "${GIT_EXECUTABLE}" -C "${SOURCE_DIR}" rev-parse HEAD
    RESULT_VARIABLE result
    OUTPUT_VARIABLE actual_revision
    ERROR_VARIABLE stderr
    OUTPUT_STRIP_TRAILING_WHITESPACE)

if(NOT result EQUAL 0)
    message(FATAL_ERROR "Unable to read Git revision: ${stderr}")
endif()

if(NOT actual_revision STREQUAL EXPECTED_REVISION)
    message(FATAL_ERROR
        "Unexpected Git revision in ${SOURCE_DIR}:\n"
        "  expected: ${EXPECTED_REVISION}\n"
        "  actual:   ${actual_revision}")
endif()

message(STATUS "Verified Git revision ${actual_revision}")
