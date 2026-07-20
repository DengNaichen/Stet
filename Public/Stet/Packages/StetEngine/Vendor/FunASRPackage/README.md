# FunASRPackage

This local package provides Stet's macOS-only, in-process Fun-ASR Nano runtime. It wraps the official FunASR `llama.cpp` implementation behind a small C ABI and ships a static XCFramework for Apple Silicon and Intel Macs.

The checked-in artifact is CPU-only, links Apple's Accelerate framework, and does not launch a helper executable. Models are downloaded separately by the app and are not bundled in the XCFramework.

The C ABI accepts optional comma-separated hotwords for each transcription. The wrapper renders them with Fun-ASR Nano's upstream context prompt while keeping the loaded model reusable across requests.

## Rebuilding

Run `./build-xcframework.sh` from this directory. The script checks out the exact upstream revisions below, builds each Mac architecture separately, localizes upstream implementation symbols behind the C ABI, combines the static archives, and replaces `Artifacts/FunASRRuntime.xcframework`.

- FunASR: `9474bdbffc349e96a4c9807a42a62309f4f02dc4`
- llama.cpp: `8086439a4cea94c71a5dfb8fe4ad1546aebd640f`

The wrapper source is derived from FunASR's `funasr-cli.cpp`. See `Licenses/` for the applicable notices.
