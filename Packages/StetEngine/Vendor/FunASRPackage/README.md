# FunASRPackage

This local package provides Stet's macOS-only, in-process Fun-ASR Nano runtime. It wraps the official FunASR `llama.cpp` implementation behind a small C ABI and ships a static XCFramework for Apple Silicon.

The checked-in artifact links Apple's Accelerate, CoreML, Foundation, and
Metal frameworks. It embeds ggml-metal and offloads the Qwen3 decoder to
the GPU. The SAN-M encoder uses a local `FunASRNanoEncoder.mlmodelc` when
present (CoreML CPU fp16 with enumerated sequence buckets), otherwise the
GGUF ggml CPU graph. Models are downloaded separately by the app and are
not bundled in the XCFramework. It does not launch a helper executable.

The C ABI accepts optional comma-separated hotwords for each transcription. The wrapper renders them with Fun-ASR Nano's upstream context prompt while keeping the loaded model reusable across requests.

## Rebuilding

Run `./build-xcframework.sh` from this directory. It builds arm64 only.
Optional `FUNASR_SOURCE_DIR` and `LLAMA_SOURCE_DIR` skip the GitHub
checkouts when those trees are already pinned locally. The script localizes
upstream implementation symbols behind the C ABI and replaces
`Artifacts/FunASRRuntime.xcframework`.

- FunASR: `9474bdbffc349e96a4c9807a42a62309f4f02dc4`
- llama.cpp: `8086439a4cea94c71a5dfb8fe4ad1546aebd640f`

The wrapper source is derived from FunASR's `funasr-cli.cpp`. See `Licenses/` for the applicable notices.
