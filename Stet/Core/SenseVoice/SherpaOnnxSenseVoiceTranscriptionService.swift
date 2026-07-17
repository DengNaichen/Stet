@preconcurrency import AVFoundation
import Foundation
import StetAI
import os

#if canImport(sherpa_onnx)
    import sherpa_onnx

    /// Convert a String from swift to a `const char*` so that we can pass it to the C language.
    private func toCPointer(_ s: String) -> UnsafePointer<Int8>! {
        let cs = (s as NSString).utf8String
        return UnsafePointer<Int8>(cs)
    }

    private func sherpaOnnxOfflineSenseVoiceModelConfig(
        model: String = "",
        language: String = "",
        useInverseTextNormalization: Bool = false
    ) -> SherpaOnnxOfflineSenseVoiceModelConfig {
        return SherpaOnnxOfflineSenseVoiceModelConfig(
            model: toCPointer(model),
            language: toCPointer(language),
            use_itn: useInverseTextNormalization ? 1 : 0
        )
    }

    private func sherpaOnnxOfflineModelConfig(
        tokens: String,
        senseVoice: SherpaOnnxOfflineSenseVoiceModelConfig,
        numThreads: Int = 1,
        provider: String = "cpu",
        debug: Int = 0
    ) -> SherpaOnnxOfflineModelConfig {
        return SherpaOnnxOfflineModelConfig(
            transducer: SherpaOnnxOfflineTransducerModelConfig(
                encoder: nil,
                decoder: nil,
                joiner: nil
            ),
            paraformer: SherpaOnnxOfflineParaformerModelConfig(model: nil),
            nemo_ctc: SherpaOnnxOfflineNemoEncDecCtcModelConfig(model: nil),
            whisper: SherpaOnnxOfflineWhisperModelConfig(
                encoder: nil,
                decoder: nil,
                language: nil,
                task: nil,
                tail_paddings: 0,
                enable_token_timestamps: 0,
                enable_segment_timestamps: 0
            ),
            tdnn: SherpaOnnxOfflineTdnnModelConfig(model: nil),
            tokens: toCPointer(tokens),
            num_threads: Int32(numThreads),
            debug: Int32(debug),
            provider: toCPointer(provider),
            model_type: nil,
            modeling_unit: toCPointer("cjkchar"),
            bpe_vocab: nil,
            telespeech_ctc: nil,
            sense_voice: senseVoice,
            moonshine: SherpaOnnxOfflineMoonshineModelConfig(
                preprocessor: nil,
                encoder: nil,
                uncached_decoder: nil,
                cached_decoder: nil,
                merged_decoder: nil
            ),
            fire_red_asr: SherpaOnnxOfflineFireRedAsrModelConfig(
                encoder: nil,
                decoder: nil
            ),
            dolphin: SherpaOnnxOfflineDolphinModelConfig(model: nil),
            zipformer_ctc: SherpaOnnxOfflineZipformerCtcModelConfig(model: nil),
            canary: SherpaOnnxOfflineCanaryModelConfig(
                encoder: nil,
                decoder: nil,
                src_lang: nil,
                tgt_lang: nil,
                use_pnc: 0
            ),
            wenet_ctc: SherpaOnnxOfflineWenetCtcModelConfig(model: nil),
            omnilingual: SherpaOnnxOfflineOmnilingualAsrCtcModelConfig(model: nil),
            medasr: SherpaOnnxOfflineMedAsrCtcModelConfig(model: nil),
            funasr_nano: SherpaOnnxOfflineFunASRNanoModelConfig(
                encoder_adaptor: nil,
                llm: nil,
                embedding: nil,
                tokenizer: nil,
                system_prompt: nil,
                user_prompt: nil,
                max_new_tokens: 0,
                temperature: 0,
                top_p: 0,
                seed: 0,
                language: nil,
                itn: 0,
                hotwords: nil
            ),
            fire_red_asr_ctc: SherpaOnnxOfflineFireRedAsrCtcModelConfig(model: nil),
            qwen3_asr: SherpaOnnxOfflineQwen3ASRModelConfig(
                conv_frontend: nil,
                encoder: nil,
                decoder: nil,
                tokenizer: nil,
                max_total_len: 0,
                max_new_tokens: 0,
                temperature: 0,
                top_p: 0,
                seed: 0,
                hotwords: nil
            ),
            cohere_transcribe: SherpaOnnxOfflineCohereTranscribeModelConfig(
                encoder: nil,
                decoder: nil,
                language: nil,
                use_punct: 0,
                use_itn: 0
            )
        )
    }

    private func sherpaOnnxFeatureConfig(
        sampleRate: Int = 16000,
        featureDim: Int = 80
    ) -> SherpaOnnxFeatureConfig {
        return SherpaOnnxFeatureConfig(
            sample_rate: Int32(sampleRate),
            feature_dim: Int32(featureDim)
        )
    }

    private func sherpaOnnxOfflineRecognizerConfig(
        featConfig: SherpaOnnxFeatureConfig,
        modelConfig: SherpaOnnxOfflineModelConfig,
        decodingMethod: String = "greedy_search",
        hotwordsPath: String? = nil,
        hotwordsScore: Float = 1.5
    ) -> SherpaOnnxOfflineRecognizerConfig {
        return SherpaOnnxOfflineRecognizerConfig(
            feat_config: featConfig,
            model_config: modelConfig,
            lm_config: SherpaOnnxOfflineLMConfig(model: nil, scale: 0),
            decoding_method: toCPointer(decodingMethod),
            max_active_paths: 4,
            hotwords_file: hotwordsPath.map { toCPointer($0) },
            hotwords_score: hotwordsScore,
            rule_fsts: nil,
            rule_fars: nil,
            blank_penalty: 0,
            hr: SherpaOnnxHomophoneReplacerConfig(
                dict_dir: nil,
                lexicon: nil,
                rule_fsts: nil
            )
        )
    }

#endif

/// Sherpa-ONNX based SenseVoice transcription service.
/// Uses ONNX Runtime instead of GGML for better memory management.
final class SherpaOnnxSenseVoiceTranscriptionService: AudioFileTranscriptionService, @unchecked Sendable {
    private let modelURL: URL
    private let tokensURL: URL
    private let recognizerLock = NSLock()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
        category: "SherpaOnnxSenseVoice"
    )

    #if canImport(sherpa_onnx)
        private var cachedRecognizer: OpaquePointer?
        private var cachedLanguageCode: String?
    #endif

    init(modelManager: SherpaOnnxSenseVoiceModelManager) throws {
        self.modelURL = try modelManager.resolvedModelURL()
        self.tokensURL = try modelManager.resolvedTokensURL()
    }

    deinit {
        #if canImport(sherpa_onnx)
            if let cachedRecognizer {
                SherpaOnnxDestroyOfflineRecognizer(cachedRecognizer)
            }
        #endif
    }

    func prewarm() async throws {
        #if canImport(sherpa_onnx)
            try withRecognizer(languageCode: nil) { _ in () }
        #else
            throw SenseVoiceError.runtimeUnavailable
        #endif
    }

    func transcribe(
        audioFileAt fileURL: URL,
        languageCode: String?,
        prompt: String?,
        audioDurationSeconds: TimeInterval?
    ) async throws -> TranscriptionResult {
        #if canImport(sherpa_onnx)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw OpenAIError.fileNotFound(fileURL)
            }

            let startedAt = ProcessInfo.processInfo.systemUptime
            let samplePreparationStartedAt = startedAt

            // Read and prepare audio samples
            let samples: [Float]
            do {
                samples = try Self.readSamples(from: fileURL)
            } catch {
                logger.error(
                    "Failed to prepare audio for SherpaOnnx SenseVoice: \(error.localizedDescription, privacy: .public)"
                )
                throw SenseVoiceError.audioPreparationFailed
            }
            let samplePreparationMs = Self.elapsedMilliseconds(since: samplePreparationStartedAt)

            let inferenceStartedAt = ProcessInfo.processInfo.systemUptime

            let result = try withRecognizer(languageCode: languageCode) { recognizer in
                guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
                    throw SenseVoiceError.transcriptionFailed
                }
                defer { SherpaOnnxDestroyOfflineStream(stream) }

                SherpaOnnxAcceptWaveformOffline(stream, 16000, samples, Int32(samples.count))
                SherpaOnnxDecodeOfflineStream(recognizer, stream)

                guard let resultPtr = SherpaOnnxGetOfflineStreamResult(stream) else {
                    throw SenseVoiceError.transcriptionFailed
                }
                defer { SherpaOnnxDestroyOfflineRecognizerResult(resultPtr) }

                let result = resultPtr.pointee
                return (
                    text: result.text != nil ? String(cString: result.text) : "",
                    detectedLanguage: Self.unwrapSpecialToken(cString: result.lang),
                    emotion: Self.unwrapSpecialToken(cString: result.emotion) ?? "",
                    event: Self.unwrapSpecialToken(cString: result.event) ?? ""
                )
            }

            let inferenceMs = Self.elapsedMilliseconds(since: inferenceStartedAt)
            let totalMs = Self.elapsedMilliseconds(since: startedAt)

            let trimmedTranscript = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTranscript.isEmpty else {
                throw SpeechServiceError.emptyTranscription
            }

            logger.info(
                "SherpaOnnx SenseVoice completed audioDurationSeconds=\(Self.formatOptionalDurationSeconds(audioDurationSeconds)) sampleCount=\(samples.count) samplePreparationMs=\(Self.formatMilliseconds(samplePreparationMs)) inferenceMs=\(Self.formatMilliseconds(inferenceMs)) totalMs=\(Self.formatMilliseconds(totalMs)) textChars=\(trimmedTranscript.count) languageCode=\(result.detectedLanguage ?? languageCode ?? "auto") emotion=\(result.emotion) event=\(result.event)"
            )

            return .init(text: trimmedTranscript, languageCode: result.detectedLanguage)
        #else
            throw SenseVoiceError.runtimeUnavailable
        #endif
    }

    #if canImport(sherpa_onnx)
        private func withRecognizer<T>(
            languageCode: String?,
            _ body: (OpaquePointer) throws -> T
        ) throws -> T {
            recognizerLock.lock()
            defer { recognizerLock.unlock() }

            let normalizedLanguageCode = "auto"  // Force auto-detection for the engine internally
            if cachedRecognizer == nil || cachedLanguageCode != normalizedLanguageCode {
                if let cachedRecognizer {
                    SherpaOnnxDestroyOfflineRecognizer(cachedRecognizer)
                }
                cachedRecognizer = try makeRecognizer(languageCode: normalizedLanguageCode)
                cachedLanguageCode = normalizedLanguageCode
            }

            guard let cachedRecognizer else {
                throw SenseVoiceError.initializationFailed
            }
            return try body(cachedRecognizer)
        }

        private func makeRecognizer(languageCode: String) throws -> OpaquePointer {
            #if !targetEnvironment(simulator)
                let provider = "coreml"
            #else
                let provider = "cpu"
            #endif

            let senseVoiceConfig = sherpaOnnxOfflineSenseVoiceModelConfig(
                model: modelURL.path,
                language: Self.normalizedSenseVoiceLanguage(languageCode),
                useInverseTextNormalization: true
            )

            let modelConfig = sherpaOnnxOfflineModelConfig(
                tokens: tokensURL.path,
                senseVoice: senseVoiceConfig,
                numThreads: max(1, min(4, ProcessInfo.processInfo.processorCount / 2)),
                provider: provider,
                debug: 0
            )

            let featConfig = sherpaOnnxFeatureConfig(
                sampleRate: 16000,
                featureDim: 80
            )

            var recognizerConfig = sherpaOnnxOfflineRecognizerConfig(
                featConfig: featConfig,
                modelConfig: modelConfig,
                decodingMethod: "greedy_search",
                hotwordsPath: nil,
                hotwordsScore: 0
            )

            guard let recognizer = SherpaOnnxCreateOfflineRecognizer(&recognizerConfig) else {
                throw SenseVoiceError.initializationFailed
            }
            return recognizer
        }
    #endif

    private nonisolated static func elapsedMilliseconds(since start: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - start) * 1_000
    }

    private nonisolated static func formatMilliseconds(_ duration: Double) -> String {
        String(format: "%.1f", duration)
    }

    private nonisolated static func formatOptionalDurationSeconds(_ duration: TimeInterval?) -> String {
        guard let duration, duration.isFinite, duration >= 0 else { return "unknown" }
        return String(format: "%.3f", duration)
    }

    private nonisolated static func unwrapSpecialToken(cString: UnsafePointer<CChar>?) -> String? {
        guard let cString else { return nil }
        var value = String(cString: cString)
        if value.hasPrefix("<|") { value.removeFirst(2) }
        if value.hasSuffix("|>") { value.removeLast(2) }
        return value.isEmpty ? nil : value
    }

    private static func normalizedSenseVoiceLanguage(_ code: String) -> String {
        let lower = code.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower == "auto" { return "auto" }

        if lower.hasPrefix("zh") { return "zh" }
        if lower.hasPrefix("en") { return "en" }
        if lower.hasPrefix("ja") { return "ja" }
        if lower.hasPrefix("ko") { return "ko" }
        if lower.hasPrefix("yue") { return "yue" }

        return "auto"
    }

    private static func readSamples(from fileURL: URL) throws -> [Float] {
        let inputFile = try AVAudioFile(forReading: fileURL)
        let inputFormat = inputFile.processingFormat
        let inputFrameCount = AVAudioFrameCount(inputFile.length)

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inputFrameCount) else {
            throw SenseVoiceError.audioPreparationFailed
        }
        try inputFile.read(into: inputBuffer)

        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false
            )
        else {
            throw SenseVoiceError.audioPreparationFailed
        }

        // Fast path: if already in correct format
        if inputFormat.channelCount == 1, inputFormat.commonFormat == .pcmFormatFloat32,
            Int(inputFormat.sampleRate) == 16000,
            let channelData = inputBuffer.floatChannelData
        {
            let frames = Int(inputBuffer.frameLength)
            return Array(UnsafeBufferPointer(start: channelData[0], count: frames))
        }

        // Need conversion
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw SenseVoiceError.audioPreparationFailed
        }
        guard
            let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: inputBuffer.frameLength)
        else {
            throw SenseVoiceError.audioPreparationFailed
        }

        var error: NSError?
        var didProvideInput = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            guard !didProvideInput else {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }
        guard status != .error, error == nil, let channelData = outputBuffer.floatChannelData else {
            throw SenseVoiceError.audioPreparationFailed
        }
        let frames = Int(outputBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: frames))
    }
}
