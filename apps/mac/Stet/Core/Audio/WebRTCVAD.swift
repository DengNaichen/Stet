import Foundation

enum WebRTCVADError: Error {
    case allocationFailed
    case invalidMode(Int)
    case invalidSampleRate(Int)
    case invalidFrameLength(Int)
}

enum WebRTCVADMode: Int, Sendable {
    case quality = 0
    case lowBitrate = 1
    case aggressive = 2
    case veryAggressive = 3
}

final class WebRTCVAD: @unchecked Sendable {
    private let handle: OpaquePointer

    init(sampleRate: Int, mode: WebRTCVADMode) throws {
        guard let handle = fvad_new() else {
            throw WebRTCVADError.allocationFailed
        }

        self.handle = handle

        guard fvad_set_sample_rate(handle, Int32(sampleRate)) == 0 else {
            fvad_free(handle)
            throw WebRTCVADError.invalidSampleRate(sampleRate)
        }

        guard fvad_set_mode(handle, Int32(mode.rawValue)) == 0 else {
            fvad_free(handle)
            throw WebRTCVADError.invalidMode(mode.rawValue)
        }
    }

    deinit {
        fvad_free(handle)
    }

    func process(frame: ArraySlice<Int16>) throws -> Bool {
        let frameLength = frame.count
        return try Array(frame).withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw WebRTCVADError.invalidFrameLength(frameLength)
            }

            let result = fvad_process(handle, baseAddress, frameLength)
            switch result {
            case 0:
                return false
            case 1:
                return true
            default:
                throw WebRTCVADError.invalidFrameLength(frameLength)
            }
        }
    }
}

@_silgen_name("fvad_new")
private func fvad_new() -> OpaquePointer?

@_silgen_name("fvad_free")
private func fvad_free(_ handle: OpaquePointer)

@_silgen_name("fvad_set_mode")
private func fvad_set_mode(_ handle: OpaquePointer, _ mode: Int32) -> Int32

@_silgen_name("fvad_set_sample_rate")
private func fvad_set_sample_rate(_ handle: OpaquePointer, _ sampleRate: Int32) -> Int32

@_silgen_name("fvad_process")
private func fvad_process(_ handle: OpaquePointer, _ frame: UnsafePointer<Int16>, _ length: Int) -> Int32
