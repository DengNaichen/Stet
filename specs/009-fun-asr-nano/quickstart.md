# Fun-ASR Nano Quickstart

## Entry Points

- Native Swift wrapper: `Packages/StetEngine/Sources/StetASR/FunASRNanoRecognizer.swift`
- Model downloads: `StetMac/Core/FunASR/FunASRNanoModelManager.swift`
- Stet service adapter: `StetMac/Core/FunASR/FunASRNanoTranscriptionService.swift`
- Engine routing: `StetMac/Core/DictationPipeline/DictationPipelineFactory.swift`
- Runtime artifact and rebuild instructions: `Packages/StetEngine/Vendor/FunASRPackage/README.md`

## Model Files

The Settings download installs these files under `~/Library/Application Support/Stet/Models/Fun-ASR-Nano/`:

- `funasr-encoder-f16.gguf`
- `qwen3-0.6b-q4km.gguf`
- `fsmn-vad.gguf`

After all three files are present, select **Fun-ASR Nano** under Settings → Audio → Local Transcription.

Enabled Personal Dictionary entries are sent to Fun-ASR Nano as recognition hotwords. When rewrite is enabled, the same entries also remain available to transcript cleanup.

## Validation

```sh
swift build --package-path Packages/StetEngine --target StetASR
make test
make ci-build
```

To run the opt-in real-model hotword smoke test after installing the three model files:

```sh
STET_FUNASR_E2E_AUDIO_PATH=/absolute/path/to/audio.mp3 \
  xcodebuild test -project Stet.xcodeproj -scheme Stet -destination 'platform=macOS,arch=arm64' \
  -only-testing:StetTests/FunASRNanoTranscriptionServiceTests
```

When Xcode does not propagate shell environment variables into the test process, place the sample at `/private/tmp/stet-funasr-e2e.mp3` instead.

The repository build also compiles `StetVisuals` Metal sources, so Xcode's matching Metal Toolchain component must be installed for the unmodified `make ci-build` command.
