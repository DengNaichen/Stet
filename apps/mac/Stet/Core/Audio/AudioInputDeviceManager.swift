#if os(macOS)
import CoreAudio
import Foundation
import Combine

struct AudioHardwareDevice: Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transportType: UInt32
}

enum AudioInputDeviceManager {
    nonisolated static func defaultInputDeviceID() -> AudioDeviceID? {
        defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    nonisolated static func defaultOutputDeviceID() -> AudioDeviceID? {
        defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    nonisolated static func defaultInputDevice() -> AudioHardwareDevice? {
        guard let deviceID = defaultInputDeviceID() else {
            return nil
        }

        return hardwareDevice(deviceID: deviceID)
    }

    nonisolated static func defaultOutputDevice() -> AudioHardwareDevice? {
        guard let deviceID = defaultOutputDeviceID() else {
            return nil
        }

        return hardwareDevice(deviceID: deviceID)
    }

    nonisolated private static func defaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else {
            AppLogger.warning("Failed to read default input device. status=\(status), deviceID=\(deviceID)")
            return nil
        }

        return deviceID
    }

    nonisolated private static func hardwareDevice(deviceID: AudioDeviceID) -> AudioHardwareDevice? {
        guard let name = deviceName(deviceID: deviceID),
              !name.isEmpty,
              let uid = deviceUID(deviceID: deviceID) else {
            return nil
        }

        return AudioHardwareDevice(
            id: deviceID,
            uid: uid,
            name: name,
            transportType: deviceTransportType(deviceID: deviceID) ?? kAudioDeviceTransportTypeUnknown
        )
    }

    nonisolated private static func deviceUID(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let valuePointer = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<CFString?>.size,
            alignment: MemoryLayout<CFString?>.alignment
        )
        defer { valuePointer.deallocate() }

        valuePointer.initializeMemory(as: CFString?.self, repeating: nil, count: 1)
        defer { valuePointer.assumingMemoryBound(to: CFString?.self).deinitialize(count: 1) }

        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            valuePointer
        )
        guard status == noErr,
              let value = valuePointer.assumingMemoryBound(to: CFString?.self).pointee else {
            return nil
        }

        return value as String
    }

    nonisolated private static func deviceTransportType(deviceID: AudioDeviceID) -> UInt32? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType = UInt32(0)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &transportType
        )
        guard status == noErr else {
            return nil
        }

        return transportType
    }

    nonisolated private static func deviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var buffer = [CChar](repeating: 0, count: 256)
        var dataSize = UInt32(buffer.count * MemoryLayout<CChar>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &buffer)
        guard status == noErr else { return nil }
        return String(cString: buffer)
    }
}

// MARK: - Interface Stubs for Compilation Testing

protocol AudioDeviceProviding: Sendable {
    func allInputDevices() -> [AudioHardwareDevice]
    func defaultInputDevice() -> AudioHardwareDevice?
}

struct SystemAudioDeviceProvider: AudioDeviceProviding {
    func allInputDevices() -> [AudioHardwareDevice] { [] }
    func defaultInputDevice() -> AudioHardwareDevice? { nil }
}

final class ThreadSafeRecordingDeviceCache: @unchecked Sendable {
    private let lock = NSLock()
    private var device: AudioHardwareDevice?
    
    func get() -> AudioHardwareDevice? {
        lock.lock()
        defer { lock.unlock() }
        return device
    }
    
    func set(_ newDevice: AudioHardwareDevice?) {
        lock.lock()
        device = newDevice
        lock.unlock()
    }
}

@MainActor
final class AudioDeviceSelectionManager: ObservableObject {
    static let shared = AudioDeviceSelectionManager(provider: SystemAudioDeviceProvider())
    
    private let provider: AudioDeviceProviding
    private let recordingCache = ThreadSafeRecordingDeviceCache()
    
    @Published private(set) var selectedDevice: AudioHardwareDevice? {
        didSet {
            recordingCache.set(selectedDevice)
        }
    }
    
    @Published private(set) var availableDevices: [AudioHardwareDevice] = []
    
    enum SelectionStrategy: String, Codable {
        case automatic
        case manual
    }
    
    @Published var strategy: SelectionStrategy = .automatic
    @Published var preferredDeviceUID: String?
    
    init(provider: AudioDeviceProviding) {
        self.provider = provider
    }
    
    nonisolated func currentRecordingDevice() -> AudioHardwareDevice? {
        return recordingCache.get()
    }
    
    func refreshDevices() {}
    func selectDevice(_ device: AudioHardwareDevice) {}
    func resetToAutomatic() {}
    func deviceForRecording() -> AudioHardwareDevice? { return nil }
    private func selectBestQualityDevice(from devices: [AudioHardwareDevice]) -> AudioHardwareDevice? { return nil }
}

final class AudioDeviceChangeMonitor {
    static let shared = AudioDeviceChangeMonitor()
    static let devicesDidChangeNotification = Notification.Name("AudioDevicesDidChange")
    private var propertyListenerBlock: AudioObjectPropertyListenerBlock?
    
    init() {}
    func startMonitoring() {}
    func stopMonitoring() {}
    deinit {}
}

@MainActor
protocol AudioTestService {
    func startRecording() async throws
    func stopRecording() async throws -> URL
    func playRecording(at url: URL) async throws
    func stopPlayback()
    func makeAudioLevelStream() -> AsyncStream<Double>
}

final class DefaultAudioTestService: AudioTestService {
    // Assuming AudioCaptureService exists, using Any for stub
    init(captureService: Any? = nil) {}
    func startRecording() async throws {}
    func stopRecording() async throws -> URL { return URL(fileURLWithPath: "") }
    func playRecording(at url: URL) async throws {}
    func stopPlayback() {}
    func makeAudioLevelStream() -> AsyncStream<Double> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

@MainActor
final class MicrophoneTestViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var audioLevel: Double = 0.0
    @Published var hasRecording = false
    
    private let audioTestService: AudioTestService
    
    init(audioTestService: AudioTestService) {
        self.audioTestService = audioTestService
    }
    
    func startRecording() async throws {}
    func stopRecording() async throws {}
    func playRecording() async throws {}
    func stopPlayback() {}
}

@MainActor
final class MenuBarDeviceSwitcher {
    private let deviceManager: AudioDeviceSelectionManager
    
    init(deviceManager: AudioDeviceSelectionManager) {
        self.deviceManager = deviceManager
    }
    
    func buildDeviceMenu() -> Any { return "Menu" } // Using Any for stub since NSMenu requires AppKit
}

#endif
