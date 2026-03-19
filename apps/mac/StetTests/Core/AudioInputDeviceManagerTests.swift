#if os(macOS)
import CoreAudio
import Foundation
import Testing

@testable import Stet

@Suite("Audio Input Device Manager", .serialized)
struct AudioInputDeviceManagerTests {
    @Test func keepsSystemDefaultWhenInputIsAlreadySafe() {
        let builtInMic = AudioHardwareDevice(
            id: 1,
            uid: "built-in-mic",
            name: "MacBook Pro Microphone",
            transportType: kAudioDeviceTransportTypeBuiltIn,
            hasInputStream: true,
            hasOutputStream: false
        )
        let speakers = AudioHardwareDevice(
            id: 2,
            uid: "studio-display",
            name: "Studio Display",
            transportType: kAudioDeviceTransportTypeBuiltIn,
            hasInputStream: false,
            hasOutputStream: true
        )

        let selection = AudioInputDeviceManager.preferredInputDeviceForDictation(
            defaultInputDevice: builtInMic,
            defaultOutputDevice: speakers,
            availableInputDevices: [builtInMic]
        )

        #expect(selection?.device == builtInMic)
        #expect(selection?.reason == .systemDefault)
    }

    @Test func fallsBackToBuiltInMicForBluetoothInput() {
        let builtInMic = AudioHardwareDevice(
            id: 1,
            uid: "built-in-mic",
            name: "MacBook Pro Microphone",
            transportType: kAudioDeviceTransportTypeBuiltIn,
            hasInputStream: true,
            hasOutputStream: false
        )
        let airPods = AudioHardwareDevice(
            id: 2,
            uid: "airpods-pro",
            name: "AirPods Pro",
            transportType: kAudioDeviceTransportTypeBluetooth,
            hasInputStream: true,
            hasOutputStream: true
        )

        let selection = AudioInputDeviceManager.preferredInputDeviceForDictation(
            defaultInputDevice: airPods,
            defaultOutputDevice: airPods,
            availableInputDevices: [airPods, builtInMic]
        )

        #expect(selection?.device == builtInMic)
        #expect(selection?.reason == .bluetoothProfileFallback)
    }

    @Test func fallsBackToBuiltInMicWhenExternalDeviceHandlesBothInputAndOutput() {
        let builtInMic = AudioHardwareDevice(
            id: 1,
            uid: "built-in-mic",
            name: "MacBook Pro Microphone",
            transportType: kAudioDeviceTransportTypeBuiltIn,
            hasInputStream: true,
            hasOutputStream: false
        )
        let usbHeadset = AudioHardwareDevice(
            id: 9,
            uid: "usb-headset",
            name: "USB Headset",
            transportType: kAudioDeviceTransportTypeUSB,
            hasInputStream: true,
            hasOutputStream: true
        )

        let selection = AudioInputDeviceManager.preferredInputDeviceForDictation(
            defaultInputDevice: usbHeadset,
            defaultOutputDevice: usbHeadset,
            availableInputDevices: [usbHeadset, builtInMic]
        )

        #expect(selection?.device == builtInMic)
        #expect(selection?.reason == .sharedExternalDeviceFallback)
    }

    @Test func keepsDefaultInputWhenNoBuiltInFallbackExists() {
        let usbHeadset = AudioHardwareDevice(
            id: 9,
            uid: "usb-headset",
            name: "USB Headset",
            transportType: kAudioDeviceTransportTypeUSB,
            hasInputStream: true,
            hasOutputStream: true
        )

        let selection = AudioInputDeviceManager.preferredInputDeviceForDictation(
            defaultInputDevice: usbHeadset,
            defaultOutputDevice: usbHeadset,
            availableInputDevices: [usbHeadset]
        )

        #expect(selection?.device == usbHeadset)
        #expect(selection?.reason == .systemDefault)
    }
}
#endif
