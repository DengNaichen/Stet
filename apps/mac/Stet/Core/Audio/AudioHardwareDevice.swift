#if os(macOS)
import CoreAudio
import Foundation

struct AudioHardwareDevice: Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transportType: UInt32
}

extension AudioHardwareDevice {
    var isBuiltIn: Bool {
        transportType == kAudioDeviceTransportTypeBuiltIn
    }

//    Unused after device prioritization moved to the transport-type switch below.
//    var isBluetooth: Bool {
//        transportType == kAudioDeviceTransportTypeBluetooth ||
//            transportType == kAudioDeviceTransportTypeBluetoothLE
//    }

    var isHandheldAppleDevice: Bool {
        let lowercaseName = name.lowercased()
        return lowercaseName.contains("iphone")
            || lowercaseName.contains("ipad")
            || lowercaseName.contains("apple iphone")
            || lowercaseName.contains("apple ipad")
    }

    var automaticSelectionPriority: AutomaticSelectionPriority {
        if isBuiltIn {
            return .builtIn
        }

        if isHandheldAppleDevice {
            return .handheldAppleDevice
        }

        switch transportType {
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypePCI, kAudioDeviceTransportTypeFireWire:
            return .externalProfessional
        case kAudioDeviceTransportTypeVirtual:
            return .virtual
        case kAudioDeviceTransportTypeAirPlay:
            return .airPlay
        case kAudioDeviceTransportTypeAggregate:
            return .aggregate
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        default:
            return .unknownExternal
        }
    }

    enum AutomaticSelectionPriority: Int, Comparable {
        case builtIn = 500
        case externalProfessional = 400
        case unknownExternal = 350
        case virtual = 300
        case airPlay = 250
        case aggregate = 200
        case bluetooth = 100
        case handheldAppleDevice = 50

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}
#endif
