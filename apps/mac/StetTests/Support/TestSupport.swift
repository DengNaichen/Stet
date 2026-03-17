import AppKit
import Foundation

@testable import Stet

enum TestSupport {
    static func makeUserDefaults(suiteName: String = "StetTests.\(UUID().uuidString)") -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    static func temporaryFileURL(_ name: String = UUID().uuidString, ext: String = "tmp") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(ext)
    }

    static func requestBodyData(from request: URLRequest) throws -> Data {
        if let httpBody = request.httpBody {
            return httpBody
        }

        guard let stream = request.httpBodyStream else {
            throw TestError.expected
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                throw stream.streamError ?? TestError.expected
            }
            if bytesRead == 0 {
                break
            }
            data.append(buffer, count: bytesRead)
        }

        return data
    }

    @MainActor
    static func eventually(
        timeout: Duration = .seconds(1),
        pollInterval: Duration = .milliseconds(10),
        condition: @MainActor @escaping () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            if condition() {
                return true
            }

            try? await Task.sleep(for: pollInterval)
        }

        return condition()
    }

    static func eventuallyAsync(
        timeout: Duration = .seconds(1),
        pollInterval: Duration = .milliseconds(10),
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            if await condition() {
                return true
            }

            try? await Task.sleep(for: pollInterval)
        }

        return await condition()
    }
}

enum TestError: Error, Equatable {
    case expected
}

final class TestSecretStore: DictationSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func loadString(forAccount account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    func saveString(_ value: String, forAccount account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.isEmpty {
            values.removeValue(forKey: account)
        } else {
            values[account] = trimmedValue
        }
    }

    func deleteString(forAccount account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: account)
    }
}

@MainActor
final class TestClipboardService: ClipboardService {
    var copiedTexts: [String] = []

    func copy(_ text: String) {
        copiedTexts.append(text)
    }
}

@MainActor
final class TestTextInjectionService: TextInjectionService {
    var isAvailable = true
    var didRequestAccess = false
    var didRequestAccessIfNeeded = false
    var didOpenAccessibilitySettings = false
    var pasteResult = true
    var selectedTextValue: String?
    var accessState = TextInjectionAccessState(
        hasAccessibilityAccess: true,
        hasPostEventAccess: true
    )
    private(set) var pasteTargets: [String?] = []
    private(set) var replacementTexts: [String] = []

    func requestAccess() {
        didRequestAccess = true
    }

    func requestAccessIfNeeded() {
        didRequestAccessIfNeeded = true
    }

    func openAccessibilitySettings() {
        didOpenAccessibilitySettings = true
    }

    func pasteClipboard(into application: NSRunningApplication?) async -> Bool {
        pasteTargets.append(application?.bundleIdentifier)
        return pasteResult
    }

    func selectedText() -> String? {
        selectedTextValue
    }

    func replaceSelectedText(
        _ text: String,
        into application: NSRunningApplication?,
        keepResultInClipboard: Bool
    ) async -> Bool {
        replacementTexts.append(text)
        pasteTargets.append(application?.bundleIdentifier)
        return pasteResult
    }
}

actor ControllableSpeechService: SpeechService, AudioLevelStreaming {
    enum StartBehavior: Sendable {
        case immediate
        case suspended
        case fail(any Error & Sendable)
    }

    enum StopBehavior: Sendable {
        case immediate(String)
        case suspended
        case fail(any Error & Sendable)
    }

    private let audioLevelBridge = AudioLevelBridge()
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var stopContinuation: CheckedContinuation<String, Error>?

    private var startBehavior: StartBehavior = .immediate
    private var stopBehavior: StopBehavior = .immediate("transcript")
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var cancelCallCount = 0

    func setStartBehavior(_ behavior: StartBehavior) {
        startBehavior = behavior
    }

    func setStopBehavior(_ behavior: StopBehavior) {
        stopBehavior = behavior
    }

    func counts() -> (start: Int, stop: Int, cancel: Int) {
        (startCallCount, stopCallCount, cancelCallCount)
    }

    func startRecording() async throws {
        startCallCount += 1

        switch startBehavior {
        case .immediate:
            return
        case .suspended:
            try await withCheckedThrowingContinuation { continuation in
                startContinuation = continuation
            }
        case .fail(let error):
            throw error
        }
    }

    func stopRecording() async throws -> String {
        stopCallCount += 1

        switch stopBehavior {
        case .immediate(let text):
            return text
        case .suspended:
            return try await withCheckedThrowingContinuation { continuation in
                stopContinuation = continuation
            }
        case .fail(let error):
            throw error
        }
    }

    func cancelRecording() async {
        cancelCallCount += 1
        startContinuation?.resume(throwing: CancellationError())
        startContinuation = nil
        stopContinuation?.resume(throwing: CancellationError())
        stopContinuation = nil
        audioLevelBridge.finish()
    }

    func allowStart() {
        startContinuation?.resume(returning: ())
        startContinuation = nil
    }

    func finishStop(with text: String) {
        stopContinuation?.resume(returning: text)
        stopContinuation = nil
    }

    func failStop(with error: any Error & Sendable = TestError.expected) {
        stopContinuation?.resume(throwing: error)
        stopContinuation = nil
    }

    func emitLevel(_ level: Double) {
        audioLevelBridge.emit(level)
    }

    func finishLevels() {
        audioLevelBridge.finish()
    }

    func makeAudioLevelStream() async -> AsyncStream<Double> {
        audioLevelBridge.makeStream()
    }
}

actor RecordingRewriteService: TextRewriteService {
    private(set) var requests: [TextRewriteRequest] = []
    private var result = "rewritten"
    private var error: (any Error & Sendable)?

    func setResult(_ result: String) {
        self.result = result
    }

    func setError(_ error: (any Error & Sendable)?) {
        self.error = error
    }

    func recordedRequests() -> [TextRewriteRequest] {
        requests
    }

    func rewrite(_ request: TextRewriteRequest) async throws -> String {
        requests.append(request)
        if let error {
            throw error
        }
        return result
    }
}

actor RecordingTranslationService: TextTranslationService {
    private(set) var requests: [TextTranslationRequest] = []
    private var result = "translated"
    private var error: (any Error & Sendable)?

    func setResult(_ result: String) {
        self.result = result
    }

    func setError(_ error: (any Error & Sendable)?) {
        self.error = error
    }

    func recordedRequests() -> [TextTranslationRequest] {
        requests
    }

    func translate(_ request: TextTranslationRequest) async throws -> String {
        requests.append(request)
        if let error {
            throw error
        }
        return result
    }
}

final class URLProtocolStub: URLProtocol {
    private static let lock = NSLock()
    private static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    static func configure(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        URLProtocolStub.lock.lock()
        let handler = URLProtocolStub.handler
        URLProtocolStub.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: TestError.expected)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

enum TestURLSessionFactory {
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}
