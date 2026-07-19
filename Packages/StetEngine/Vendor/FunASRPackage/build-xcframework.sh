#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
RUNTIME_DIR="$SCRIPT_DIR/RuntimeSource"
OUTPUT_DIR="$SCRIPT_DIR/Artifacts"
OUTPUT_XCFRAMEWORK="$OUTPUT_DIR/FunASRRuntime.xcframework"
FUNASR_COMMIT=9474bdbffc349e96a4c9807a42a62309f4f02dc4
LLAMA_COMMIT=8086439a4cea94c71a5dfb8fe4ad1546aebd640f
BUILD_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stet-funasr-build.XXXXXX")
trap 'rm -rf "$BUILD_ROOT"' EXIT

git clone --filter=blob:none --no-checkout https://github.com/modelscope/FunASR.git "$BUILD_ROOT/FunASR"
git -C "$BUILD_ROOT/FunASR" sparse-checkout init --cone
git -C "$BUILD_ROOT/FunASR" sparse-checkout set runtime/llama.cpp
git -C "$BUILD_ROOT/FunASR" checkout "$FUNASR_COMMIT"

git clone --filter=blob:none https://github.com/ggml-org/llama.cpp.git "$BUILD_ROOT/llama.cpp"
git -C "$BUILD_ROOT/llama.cpp" checkout "$LLAMA_COMMIT"

typeset -a ARCH_LIBRARIES
for ARCHITECTURE in arm64 x86_64; do
    ARCH_BUILD_DIR="$BUILD_ROOT/build-$ARCHITECTURE"
    cmake \
        -S "$RUNTIME_DIR" \
        -B "$ARCH_BUILD_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="$ARCHITECTURE" \
        -DCMAKE_SYSTEM_PROCESSOR="$ARCHITECTURE" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
        -DFUNASR_SOURCE_DIR="$BUILD_ROOT/FunASR" \
        -DLLAMA_SOURCE_DIR="$BUILD_ROOT/llama.cpp"
    cmake --build "$ARCH_BUILD_DIR" --target StetFunASRRuntime --parallel

    COMBINED_LIBRARY="$BUILD_ROOT/libFunASRRuntime-$ARCHITECTURE.a"
    libtool -static -o "$COMBINED_LIBRARY" \
        "$ARCH_BUILD_DIR/libStetFunASRRuntime.a" \
        "$ARCH_BUILD_DIR/llama/src/libllama.a" \
        "$ARCH_BUILD_DIR/llama/ggml/src/libggml.a" \
        "$ARCH_BUILD_DIR/llama/ggml/src/libggml-base.a" \
        "$ARCH_BUILD_DIR/llama/ggml/src/libggml-cpu.a" \
        "$ARCH_BUILD_DIR/llama/ggml/src/ggml-blas/libggml-blas.a"
    ARCH_LIBRARIES+=("$COMBINED_LIBRARY")
done

UNIVERSAL_LIBRARY="$BUILD_ROOT/libFunASRRuntime.a"
lipo -create "${ARCH_LIBRARIES[@]}" -output "$UNIVERSAL_LIBRARY"
mkdir -p "$OUTPUT_DIR"
if [[ -e "$OUTPUT_XCFRAMEWORK" ]]; then
    mv "$OUTPUT_XCFRAMEWORK" "$BUILD_ROOT/previous.xcframework"
fi
xcodebuild -create-xcframework \
    -library "$UNIVERSAL_LIBRARY" \
    -headers "$RUNTIME_DIR/include" \
    -output "$OUTPUT_XCFRAMEWORK"
