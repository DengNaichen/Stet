cmake_minimum_required(VERSION 3.20)
project(StetFunASRRuntime LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)
add_compile_options(-fno-common)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)

set(GGML_CPU_ARM_ARCH "armv8.2-a+dotprod+fp16" CACHE STRING "" FORCE)
# Embed the metallib so the XCFramework does not need a sidecar .metallib.
set(GGML_METAL ON CACHE BOOL "" FORCE)
set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)

if(NOT DEFINED FUNASR_SOURCE_DIR)
    message(FATAL_ERROR "FUNASR_SOURCE_DIR must point to a FunASR checkout")
endif()

if(NOT DEFINED LLAMA_SOURCE_DIR)
    message(FATAL_ERROR "LLAMA_SOURCE_DIR must point to the pinned llama.cpp checkout")
endif()

add_subdirectory("${LLAMA_SOURCE_DIR}" llama EXCLUDE_FROM_ALL)

add_library(StetFunASRRuntime STATIC stet_funasr.cpp stet_funasr_coreml.mm)
target_include_directories(StetFunASRRuntime
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include"
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}"
        "${FUNASR_SOURCE_DIR}/runtime/llama.cpp/funasr-common"
)
target_compile_options(StetFunASRRuntime PRIVATE
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>
)
target_link_libraries(StetFunASRRuntime PRIVATE
    llama
    ggml
    "-framework Foundation"
    "-framework CoreML"
)
target_compile_definitions(StetFunASRRuntime PRIVATE GGML_USE_ACCELERATE)
if(GGML_METAL)
    target_compile_definitions(StetFunASRRuntime PRIVATE GGML_USE_METAL)
endif()
set_target_properties(StetFunASRRuntime PROPERTIES
    OUTPUT_NAME StetFunASRRuntime
    POSITION_INDEPENDENT_CODE ON
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO
)

install(TARGETS StetFunASRRuntime ARCHIVE DESTINATION lib)
install(FILES include/stet_funasr.h DESTINATION include)
