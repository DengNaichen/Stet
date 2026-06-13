import Foundation
import AVFoundation
import whisper

public final class WhisperASREngine: ASREngine {
    public let name = "Whisper-CPP"
    
    private let modelManager: ASRModelManager
    private let lock = NSLock()
    private var samples: [Float] = []
    private var isRecording = false
    private var activeSessionId: String?
    
    private var context: OpaquePointer?
    private static let inferenceQueue = DispatchQueue(label: "com.stet.StetASR.whisper.inference", qos: .utility)
    
    public let resultStream: AsyncStream<ASRResult>
    private let continuation: AsyncStream<ASRResult>.Continuation

    public init(modelManager: ASRModelManager) {
        self.modelManager = modelManager
        let (stream, cont) = AsyncStream<ASRResult>.makeStream()
        self.resultStream = stream
        self.continuation = cont
    }
    
    deinit {
        if let context {
            whisper_free(context)
        }
    }

    public func prepare() async throws {
        try await loadModelIfNeeded()
    }

    public func start(sessionId: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        
        activeSessionId = sessionId
        samples.removeAll()
        isRecording = true
    }
    
    public func acceptAudio(samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        guard isRecording else { return }
        self.samples.append(contentsOf: samples)
    }

    public func stop() {
        lock.lock()
        let currentSamples = self.samples
        let sessionId = self.activeSessionId
        isRecording = false
        lock.unlock()
        
        guard let sessionId = sessionId, !currentSamples.isEmpty else {
            return
        }
        
        Task {
            do {
                let result = try await performTranscription(samples: currentSamples)
                continuation.yield(result)
            } catch {
                // Yield empty result or error
                continuation.yield(ASRResult(text: "", isFinal: true))
            }
        }
    }

    public func teardown() {
        lock.lock()
        defer { lock.unlock() }
        isRecording = false
        activeSessionId = nil
        if let context {
            whisper_free(context)
            self.context = nil
        }
        continuation.finish()
    }

    private func loadModelIfNeeded() async throws {
        guard context == nil else { return }
        
        let urls = try await modelManager.resolveModelURLs(for: "Whisper")
        guard let modelURL = urls["model"] else {
            throw NSError(domain: "StetASR", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing Whisper model path"])
        }
        
        var params = whisper_context_default_params()
        #if !targetEnvironment(simulator)
            params.flash_attn = true
        #else
            params.use_gpu = false
        #endif

        guard let loadedContext = whisper_init_from_file_with_params(modelURL.path, params) else {
            throw NSError(domain: "StetASR", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Whisper context"])
        }
        self.context = loadedContext
    }
    
    private func performTranscription(samples: [Float]) async throws -> ASRResult {
        guard let ctx = context else { throw NSError(domain: "StetASR", code: 5, userInfo: [NSLocalizedDescriptionKey: "Whisper context not initialized"]) }
        
        let wallStart = CFAbsoluteTimeGetCurrent()
        let nThreads = Int32(max(1, min(4, ProcessInfo.processInfo.processorCount / 2)))
        
        let success = await withCheckedContinuation { continuation in
            Self.inferenceQueue.async {
                var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
                params.print_realtime = false
                params.print_progress = false
                params.print_timestamps = false
                params.print_special = false
                params.translate = false
                params.no_context = true
                params.temperature = 0
                params.n_threads = nThreads
                params.beam_search.beam_size = 5
                
                var success = true
                samples.withUnsafeBufferPointer { buffer in
                    if whisper_full(ctx, params, buffer.baseAddress, Int32(buffer.count)) != 0 {
                        success = false
                    }
                }
                continuation.resume(returning: success)
            }
        }
        
        guard success else {
            throw NSError(domain: "StetASR", code: 6, userInfo: [NSLocalizedDescriptionKey: "Whisper transcription failed"])
        }
        
        var text = ""
        for index in 0..<whisper_full_n_segments(ctx) {
            if let cStr = whisper_full_get_segment_text(ctx, index) {
                text += String(cString: cStr)
            }
        }
        
        let wallDuration = CFAbsoluteTimeGetCurrent() - wallStart
        let audioDuration = Double(samples.count) / 16000.0
        
        let metrics = ASRMetrics(
            audioDuration: audioDuration,
            cpuDuration: wallDuration, // Approximation
            wallDuration: wallDuration,
            rtf: audioDuration > 0 ? wallDuration / audioDuration : 0
        )
        
        return ASRResult(text: text.trimmingCharacters(in: .whitespacesAndNewlines), isFinal: true, metrics: metrics)
    }
}
