#if os(macOS)
    import Testing

    @testable import Stet

    @Suite("Mac Feature Availability")
    struct MacFeatureAvailabilityTests {
        @Test func passiveListeningRuntimeFollowsVisibilityGate() {
            #expect(!MacFeatureAvailability.isPassiveListeningEnabled(preference: false))
            #expect(
                MacFeatureAvailability.isPassiveListeningEnabled(preference: true)
                    == MacFeatureAvailability.isPassiveListeningVisible
            )
        }
    }
#endif
