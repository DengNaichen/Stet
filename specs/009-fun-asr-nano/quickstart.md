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

## Validation

```sh
swift build --package-path Packages/StetEngine --target StetASR
make test
make ci-build
```

The repository build also compiles `StetVisuals` Metal sources, so Xcode's matching Metal Toolchain component must be installed for the unmodified `make ci-build` command.
