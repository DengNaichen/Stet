import Foundation
#if canImport(TelemetryDeck)
    import TelemetryDeck
#endif

enum AnalyticsService {
    static func initialize() {
        let appID =
            ProcessInfo.processInfo.environment["TELEMETRY_DECK_APP_ID"] ?? "BEB795DB-6ADC-4D8B-9159-4F2D6B847933"

        #if canImport(TelemetryDeck)
            TelemetryDeck.initialize(config: .init(appID: appID))
        #endif
    }

    static func track(_ signal: String, parameters: [String: String] = [:]) {
        #if canImport(TelemetryDeck)
            TelemetryDeck.signal(signal, parameters: parameters)
        #endif
    }
}
