import AVFoundation

extension AudioBuffer {
    func floatArray() -> [Float] {
        Array(UnsafeBufferPointer(self))
    }
}

extension AVAudioPCMBuffer {
    func floatArray() -> [Float] {
        audioBufferList.pointee.mBuffers.floatArray()
    }
}
