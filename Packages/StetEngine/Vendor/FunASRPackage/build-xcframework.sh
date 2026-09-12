#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
RUNTIME_DIR="$SCRIPT_DIR/RuntimeSource"
OUTPUT_DIR="$SCRIPT_DIR/Artifacts"
OUTPUT_XCFRAMEWORK="$OUTPUT_DIR/FunASRRuntime.xcframework"
FUNASR_COMMIT=9474bdbffc349e96a4c9807a42a62309f4f02dc4
LLAMA_COMMIT=8086439a4cea94c71a5dfb8fe4ad1546aebd640f
BUILD_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stet-funasr-build.XXXXXX")
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
trap 'rm -rf "$BUILD_ROOT"' EXIT

typeset -a BUILD_ARCHS
BUILD_ARCHS=(arm64)

github_clone() {
    local dest="$1"
    local repo_path="$2"
    shift 2
    local urls=(
        "https://github.com/${repo_path}"
        "https://ghfast.top/https://github.com/${repo_path}"
        "https://gitclone.com/github.com/${repo_path}"
    )
    local url
    for url in "${urls[@]}"; do
        echo "Cloning ${url}"
        if GIT_TERMINAL_PROMPT=0 \
            GIT_HTTP_LOW_SPEED_LIMIT=1024 \
            GIT_HTTP_LOW_SPEED_TIME=20 \
            git clone "$@" "$url" "$dest"; then
            return 0
        fi
        rm -rf "$dest"
    done
    echo "failed to clone ${repo_path} from GitHub and China mirrors" >&2
    return 1
}

if [[ -z "${FUNASR_SOURCE_DIR:-}" ]]; then
    github_clone "$BUILD_ROOT/FunASR" "modelscope/FunASR.git" --filter=blob:none --no-checkout
    git -C "$BUILD_ROOT/FunASR" sparse-checkout init --cone
    git -C "$BUILD_ROOT/FunASR" sparse-checkout set runtime/llama.cpp
    git -C "$BUILD_ROOT/FunASR" checkout "$FUNASR_COMMIT"
    FUNASR_SOURCE_DIR="$BUILD_ROOT/FunASR"
fi

if [[ -z "${LLAMA_SOURCE_DIR:-}" ]]; then
    github_clone "$BUILD_ROOT/llama.cpp" "ggml-org/llama.cpp.git" --filter=blob:none
    git -C "$BUILD_ROOT/llama.cpp" checkout "$LLAMA_COMMIT"
    LLAMA_SOURCE_DIR="$BUILD_ROOT/llama.cpp"
fi

typeset -a ARCH_LIBRARIES
for ARCHITECTURE in "${BUILD_ARCHS[@]}"; do
    ARCH_BUILD_DIR="$BUILD_ROOT/build-$ARCHITECTURE"
    cmake \
        -S "$RUNTIME_DIR" \
        -B "$ARCH_BUILD_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="$ARCHITECTURE" \
        -DCMAKE_SYSTEM_PROCESSOR="$ARCHITECTURE" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
        -DFUNASR_SOURCE_DIR="$FUNASR_SOURCE_DIR" \
        -DLLAMA_SOURCE_DIR="$LLAMA_SOURCE_DIR"
    cmake --build "$ARCH_BUILD_DIR" --target StetFunASRRuntime --parallel

    typeset -a ARCH_OBJECTS
    ARCH_OBJECTS=(
        "$ARCH_BUILD_DIR/libStetFunASRRuntime.a"
        "$ARCH_BUILD_DIR/llama/src/libllama.a"
        "$ARCH_BUILD_DIR/llama/ggml/src/libggml.a"
        "$ARCH_BUILD_DIR/llama/ggml/src/libggml-base.a"
        "$ARCH_BUILD_DIR/llama/ggml/src/libggml-cpu.a"
        "$ARCH_BUILD_DIR/llama/ggml/src/ggml-blas/libggml-blas.a"
    )
    if [[ "$ARCHITECTURE" == arm64 ]]; then
        ARCH_OBJECTS+=("$ARCH_BUILD_DIR/llama/ggml/src/ggml-metal/libggml-metal.a")
    fi

    COMBINED_OBJECT="$BUILD_ROOT/FunASRRuntime-$ARCHITECTURE.o"
    ld -r \
        -arch "$ARCHITECTURE" \
        -platform_version macos 14.0 "$SDK_VERSION" \
        -o "$COMBINED_OBJECT" \
        -all_load \
        "${ARCH_OBJECTS[@]}"
    nmedit -s "$RUNTIME_DIR/exported_symbols.txt" "$COMBINED_OBJECT"

    COMBINED_LIBRARY="$BUILD_ROOT/libFunASRRuntime-$ARCHITECTURE.a"
    libtool -static -o "$COMBINED_LIBRARY" "$COMBINED_OBJECT"
    ARCH_LIBRARIES+=("$COMBINED_LIBRARY")
done

UNIVERSAL_LIBRARY="$BUILD_ROOT/libFunASRRuntime.a"
cp "${ARCH_LIBRARIES[1]}" "$UNIVERSAL_LIBRARY"
mkdir -p "$OUTPUT_DIR"
if [[ -e "$OUTPUT_XCFRAMEWORK" ]]; then
    mv "$OUTPUT_XCFRAMEWORK" "$BUILD_ROOT/previous.xcframework"
fi
xcodebuild -create-xcframework \
    -library "$UNIVERSAL_LIBRARY" \
    -headers "$RUNTIME_DIR/include" \
    -output "$OUTPUT_XCFRAMEWORK"
