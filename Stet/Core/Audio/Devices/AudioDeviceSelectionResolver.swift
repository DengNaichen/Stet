#if os(macOS)
    struct AudioDeviceSelectionResolver {
        enum Preference: Equatable, Sendable {
            case builtInDefault
            case external(uid: String)
        }

        struct Resolution: Equatable, Sendable {
            let preference: Preference
            let activeDevice: AudioHardwareDevice?
            let isUsingFallbackBuiltIn: Bool
        }

        static func resolve(
            availableDevices: [AudioHardwareDevice],
            defaultInputDevice: AudioHardwareDevice?,
            preferredAudioInputDeviceUID: String?
        ) -> Resolution {
            let preference = preferredAudioInputDeviceUID.map { Preference.external(uid: $0) } ?? .builtInDefault
            return resolve(
                availableDevices: availableDevices,
                defaultInputDevice: defaultInputDevice,
                preference: preference
            )
        }

        static func resolve(
            availableDevices: [AudioHardwareDevice],
            defaultInputDevice: AudioHardwareDevice?,
            preference: Preference
        ) -> Resolution {
            switch preference {
            case .builtInDefault:
                return Resolution(
                    preference: preference,
                    activeDevice: defaultBuiltInRoute(
                        availableDevices: availableDevices,
                        defaultInputDevice: defaultInputDevice
                    ),
                    isUsingFallbackBuiltIn: false
                )

            case .external(let uid):
                if let preferredDevice = availableDevices.first(where: { $0.uid == uid }) {
                    return Resolution(
                        preference: preference,
                        activeDevice: preferredDevice,
                        isUsingFallbackBuiltIn: false
                    )
                }

                let fallbackDevice = defaultBuiltInRoute(
                    availableDevices: availableDevices,
                    defaultInputDevice: defaultInputDevice
                )
                return Resolution(
                    preference: preference,
                    activeDevice: fallbackDevice,
                    isUsingFallbackBuiltIn: fallbackDevice?.isBuiltIn == true
                )
            }
        }

        private static func defaultBuiltInRoute(
            availableDevices: [AudioHardwareDevice],
            defaultInputDevice: AudioHardwareDevice?
        ) -> AudioHardwareDevice? {
            if let builtInDevice = availableDevices.first(where: \.isBuiltIn) {
                return builtInDevice
            }

            if let defaultInputDevice {
                if let matchingDefaultDevice = availableDevices.first(where: { $0.uid == defaultInputDevice.uid }) {
                    return matchingDefaultDevice
                }

                if availableDevices.isEmpty {
                    return defaultInputDevice
                }
            }

            return availableDevices.max(by: { $0.automaticSelectionPriority < $1.automaticSelectionPriority })
        }
    }
#endif
