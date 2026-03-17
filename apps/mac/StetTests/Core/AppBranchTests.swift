#if os(macOS)
import Testing

@testable import Stet

@Suite("Network Proxy Models")
struct NetworkProxyModelTests {
    @Test(arguments: [
        (NetworkProxyMode.system, "System"),
        (.disabled, "Direct"),
        (.custom, "Custom"),
    ])
    func networkProxyModeTitle(_ mode: NetworkProxyMode, expectedTitle: String) {
        #expect(mode.title == expectedTitle)
    }

    @Test(arguments: [
        (CustomProxyScheme.http, "HTTP"),
        (.https, "HTTPS"),
        (.socks5, "SOCKS5"),
    ])
    func customProxySchemeTitle(_ scheme: CustomProxyScheme, expectedTitle: String) {
        #expect(scheme.title == expectedTitle)
    }

    @Test func networkProxySettingsRequiresHostAndPortForCustomEndpoint() {
        #expect(
            !NetworkProxySettings(
                mode: .custom,
                customScheme: .https,
                customHost: "",
                customPort: 8443
            ).hasCustomEndpoint
        )
        #expect(
            !NetworkProxySettings(
                mode: .custom,
                customScheme: .https,
                customHost: "proxy.example.com",
                customPort: nil
            ).hasCustomEndpoint
        )
        #expect(
            NetworkProxySettings(
                mode: .custom,
                customScheme: .https,
                customHost: "proxy.example.com",
                customPort: 8443
            ).hasCustomEndpoint
        )
    }
}
#endif
