cmake_minimum_required(VERSION 3.20)
project(FunASRANEProbe LANGUAGES C CXX OBJC OBJCXX)
set(CMAKE_CXX_STANDARD 17)
add_subdirectory(../../Packages/StetEngine/Vendor/FunASRPackage/RuntimeSource runtime)
add_executable(funasr-encoder-probe probe.cpp)
target_include_directories(funasr-encoder-probe PRIVATE
    ../../Packages/StetEngine/Vendor/FunASRPackage/RuntimeSource/include
    "${FUNASR_SOURCE_DIR}/runtime/llama.cpp/funasr-common")
target_link_libraries(funasr-encoder-probe PRIVATE llama ggml)
add_executable(funasr-decode-probe decode_probe.cpp)
target_include_directories(funasr-decode-probe PRIVATE
    ../../Packages/StetEngine/Vendor/FunASRPackage/RuntimeSource/include
    "${FUNASR_SOURCE_DIR}/runtime/llama.cpp/funasr-common")
target_link_libraries(funasr-decode-probe PRIVATE llama ggml)
if(GGML_METAL)
    target_compile_definitions(funasr-decode-probe PRIVATE GGML_USE_METAL)
endif()

foreach(probe funasr-encoder-probe funasr-decode-probe)
    target_sources(${probe} PRIVATE ../../Packages/StetEngine/Vendor/FunASRPackage/RuntimeSource/stet_funasr_coreml.mm)
    target_link_libraries(${probe} PRIVATE "-framework CoreML" "-framework Foundation")
    target_compile_options(${probe} PRIVATE $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
endforeach()
add_executable(funasr-transcribe-probe transcribe_probe.cpp)
target_link_libraries(funasr-transcribe-probe PRIVATE StetFunASRRuntime)
add_executable(funasr-sequence-probe sequence_probe.cpp)
target_include_directories(funasr-sequence-probe PRIVATE ../../Packages/StetEngine/Vendor/FunASRPackage/RuntimeSource)
target_link_libraries(funasr-sequence-probe PRIVATE StetFunASRRuntime)
