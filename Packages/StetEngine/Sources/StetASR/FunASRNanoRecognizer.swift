#if os(macOS)
    import Foundation
    import StetCore
    import FunASRRuntime

    public struct FunASRNanoModelFiles: Equatable, Sendable {
        public let encoder: URL
        public let languageModel: URL
        public let voiceActivityDetector: URL

        public init(encoder: URL, languageModel: URL, voiceActivityDetector: URL) {
            self.encoder = encoder
            self.languageModel = languageModel
            self.voiceActivityDetector = voiceActivityDetector
        }

        public var allFiles: [URL] {
            [encoder, languageModel, voiceActivityDetector]
        }
    }

    public enum FunASRNanoRecognizerError: LocalizedError, Equatable, Sendable {
        case missingModel(URL)
        case modelLoadFailed(String)
        case transcriptionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .missingModel(let url):
                return "Fun-ASR model component is missing at \(url.path)."
            case .modelLoadFailed(let message):
                return "Fun-ASR could not load its models: \(message)"
            case .transcriptionFailed(let message):
                return "Fun-ASR transcription failed: \(message)"
            }
        }
    }

    public final class FunASRNanoResidentEncoder: @unchecked Sendable {
        public let modelURL: URL
        private let lock = NSLock()
        private var handle: OpaquePointer?

        public init(modelURL: URL) throws {
            guard FileManager.default.fileExists(atPath: modelURL.path) else {
                throw FunASRNanoRecognizerError.missingModel(modelURL)
            }
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let loadedHandle = modelURL.path.withCString { encoderPath in
                errorBuffer.withUnsafeMutableBufferPointer { buffer in
                    stet_funasr_encoder_create(encoderPath, buffer.baseAddress, buffer.count)
                }
            }
            guard let loadedHandle else {
                throw FunASRNanoRecognizerError.modelLoadFailed(
                    FunASRNanoRecognizer.message(from: errorBuffer)
                )
            }
            self.modelURL = modelURL
            self.handle = loadedHandle
        }

        deinit {
            releaseResources()
        }

        public func warmup() throws {
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let succeeded: Int32 = withUnsafeHandle { pointer in
                guard let pointer else { return 0 }
                return errorBuffer.withUnsafeMutableBufferPointer { buffer in
                    stet_funasr_encoder_warmup(pointer, buffer.baseAddress, buffer.count)
                }
            }
            guard succeeded != 0 else {
                throw FunASRNanoRecognizerError.modelLoadFailed(
                    FunASRNanoRecognizer.message(from: errorBuffer)
                )
            }
        }

        public func releaseResources() {
            let existing: OpaquePointer? = {
                lock.lock()
                defer { lock.unlock() }
                let current = handle
                handle = nil
                return current
            }()
            if let existing {
                stet_funasr_encoder_destroy(existing)
            }
        }

        func withUnsafeHandle<R>(_ body: (OpaquePointer?) throws -> R) rethrows -> R {
            lock.lock()
            defer { lock.unlock() }
            return try body(handle)
        }
    }

    public actor FunASRNanoRecognizer {
        private nonisolated let executor = DispatchQueueSerialExecutor(
            label: "Stet.FunASRNano.runtime"
        )
        public nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }

        private let modelFiles: FunASRNanoModelFiles
        private var residentEncoder: FunASRNanoResidentEncoder?
        private let threadCount: Int32
        private var context: OpaquePointer?

        public init(
            modelFiles: FunASRNanoModelFiles,
            residentEncoder: FunASRNanoResidentEncoder? = nil,
            threadCount: Int = max(1, min(4, ProcessInfo.processInfo.processorCount / 2))
        ) {
            self.modelFiles = modelFiles
            self.residentEncoder = residentEncoder
            self.threadCount = Int32(max(1, threadCount))
        }

        deinit {
            if let context {
                stet_funasr_destroy(context)
            }
        }

        public func prepare() throws {
            guard context == nil else { return }

            for fileURL in modelFiles.allFiles where !FileManager.default.fileExists(atPath: fileURL.path) {
                throw FunASRNanoRecognizerError.missingModel(fileURL)
            }

            var errorBuffer = [CChar](repeating: 0, count: 512)
            let loadedContext = modelFiles.encoder.path.withCString { encoderPath in
                modelFiles.languageModel.path.withCString { languageModelPath in
                    modelFiles.voiceActivityDetector.path.withCString { vadPath in
                        errorBuffer.withUnsafeMutableBufferPointer { buffer in
                            if let residentEncoder {
                                return residentEncoder.withUnsafeHandle { sharedPointer in
                                    stet_funasr_create_with_encoder(
                                        encoderPath,
                                        sharedPointer,
                                        languageModelPath,
                                        vadPath,
                                        threadCount,
                                        buffer.baseAddress,
                                        buffer.count
                                    )
                                }
                            }
                            return stet_funasr_create(
                                encoderPath,
                                languageModelPath,
                                vadPath,
                                threadCount,
                                buffer.baseAddress,
                                buffer.count
                            )
                        }
                    }
                }
            }

            guard let loadedContext else {
                throw FunASRNanoRecognizerError.modelLoadFailed(Self.message(from: errorBuffer))
            }
            context = loadedContext
        }

        public func updateResidentEncoder(_ encoder: FunASRNanoResidentEncoder?) {
            self.residentEncoder = encoder
            guard let context else { return }
            if let encoder {
                encoder.withUnsafeHandle { sharedPointer in
                    stet_funasr_set_shared_encoder(context, sharedPointer)
                }
            } else {
                stet_funasr_set_shared_encoder(context, nil)
            }
        }

        public func transcribe(
            audioFileURL: URL,
            maximumTokens: Int = 512,
            hotwords: String? = nil
        ) throws -> String {
            try prepare()
            guard let context else {
                throw FunASRNanoRecognizerError.modelLoadFailed("runtime context is unavailable")
            }

            var output: UnsafeMutablePointer<CChar>?
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let normalizedHotwords = hotwords?.trimmingCharacters(in: .whitespacesAndNewlines)
            let status = audioFileURL.path.withCString { audioPath in
                func transcribe(hotwords: UnsafePointer<CChar>?) -> stet_funasr_status {
                    errorBuffer.withUnsafeMutableBufferPointer { buffer in
                        stet_funasr_transcribe(
                            context,
                            audioPath,
                            Int32(max(1, maximumTokens)),
                            hotwords,
                            &output,
                            buffer.baseAddress,
                            buffer.count
                        )
                    }
                }

                if let normalizedHotwords, !normalizedHotwords.isEmpty {
                    return normalizedHotwords.withCString { transcribe(hotwords: $0) }
                }
                return transcribe(hotwords: nil)
            }

            guard status == STET_FUNASR_OK, let output else {
                throw FunASRNanoRecognizerError.transcriptionFailed(Self.message(from: errorBuffer))
            }
            defer { stet_funasr_free_text(output) }
            return String(cString: output)
        }

        public func encoderBackend() -> String {
            guard let context else { return "unloaded" }
            return String(cString: stet_funasr_encoder_backend(context))
        }

        public func releaseResources() {
            if let context {
                stet_funasr_destroy(context)
                self.context = nil
            }
        }

        fileprivate nonisolated static func message(from buffer: [CChar]) -> String {
            buffer.withUnsafeBufferPointer { pointer in
                guard let baseAddress = pointer.baseAddress, baseAddress.pointee != 0 else {
                    return "unknown runtime error"
                }
                return String(cString: baseAddress)
            }
        }
    }
#endif
