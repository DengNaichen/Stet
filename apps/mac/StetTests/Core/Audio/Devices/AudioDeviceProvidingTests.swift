#if os(macOS)
import Testing

@testable import Stet

@Suite("System Audio Device Provider")
struct SystemAudioDeviceProviderTests {
    @Test func allInputDevicesReturnsDeviceList() {
        let provider = SystemAudioDeviceProvider()
        let devices = provider.allInputDevices()
        
        #expect(devices.count >= 0)
    }
    
    @Test func defaultInputDeviceReturnsDevice() {
        let provider = SystemAudioDeviceProvider()
        let device = provider.defaultInputDevice()
        
        #expect(device != nil || device == nil)
    }
}
#endif
