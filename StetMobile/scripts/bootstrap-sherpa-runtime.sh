#!/usr/bin/env bash

set -euo pipefail

readonly runtime_version="1.13.4"
readonly archive_name="sherpa-onnx-v${runtime_version}-ios-no-tts.tar.bz2"
readonly runtime_url="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${runtime_version}/${archive_name}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mobile_root="$(cd -- "${script_dir}/.." && pwd)"
runtime_root="${mobile_root}/.runtime/sherpa-onnx-v${runtime_version}"
runtime_contents_root="${runtime_root}/build-ios-no-tts"
sherpa_runtime="${runtime_contents_root}/sherpa-onnx.xcframework"
onnx_runtime_root="${runtime_contents_root}/ios-onnxruntime"
sherpa_link="${mobile_root}/Frameworks/sherpa-onnx.xcframework"
onnx_link="${mobile_root}/Frameworks/ios-onnxruntime/onnxruntime.xcframework"

runtime_is_ready() {
    local onnx_candidates=("${onnx_runtime_root}"/*/onnxruntime.xcframework)
    [[ -d "${sherpa_runtime}" && ${#onnx_candidates[@]} -eq 1 && -d "${onnx_candidates[0]}" ]]
}

if ! runtime_is_ready; then
    temporary_directory="$(mktemp -d)"
    trap 'rm -rf "${temporary_directory}"' EXIT

    mkdir -p "${runtime_root}"
    curl --fail --location --retry 3 --output "${temporary_directory}/${archive_name}" "${runtime_url}"
    tar -xjf "${temporary_directory}/${archive_name}" --strip-components=1 -C "${runtime_root}"
fi

onnx_candidates=("${onnx_runtime_root}"/*/onnxruntime.xcframework)
if [[ ! -d "${sherpa_runtime}" ]]; then
    echo "Missing Sherpa runtime after extraction: ${sherpa_runtime}" >&2
    exit 1
fi
if [[ ${#onnx_candidates[@]} -ne 1 || ! -d "${onnx_candidates[0]}" ]]; then
    echo "Expected exactly one ONNX Runtime framework under: ${onnx_runtime_root}" >&2
    exit 1
fi

onnx_runtime="${onnx_candidates[0]}"
onnx_runtime_version="$(basename -- "$(dirname -- "${onnx_runtime}")")"
sherpa_target="../.runtime/sherpa-onnx-v${runtime_version}/build-ios-no-tts/sherpa-onnx.xcframework"
onnx_target="../../.runtime/sherpa-onnx-v${runtime_version}/build-ios-no-tts/ios-onnxruntime/${onnx_runtime_version}/onnxruntime.xcframework"

for link in "${sherpa_link}" "${onnx_link}"; do
    if [[ -e "${link}" && ! -L "${link}" ]]; then
        echo "Refusing to replace non-symlink runtime path: ${link}" >&2
        exit 1
    fi
done

ln -sfn "${sherpa_target}" "${sherpa_link}"
ln -sfn "${onnx_target}" "${onnx_link}"
