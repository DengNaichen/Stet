#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("Clipboard Service", .serialized)
struct ClipboardServiceTests {
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("StetTests.Clipboard.\(UUID().uuidString)"))
    }

    @Test func transientCopiesMarkPasteboardAsTransient() {
        let pasteboard = makePasteboard()
        let clipboard = SystemClipboardService(pasteboard: pasteboard)

        clipboard.copy("temporary", transient: true)

        #expect(pasteboard.string(forType: .string) == "temporary")
        #expect(
            pasteboard.data(
                forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) != nil
        )
    }

    @Test func persistentCopiesDoNotMarkPasteboardAsTransient() {
        let pasteboard = makePasteboard()
        let clipboard = SystemClipboardService(pasteboard: pasteboard)

        clipboard.copy("persistent", transient: false)

        #expect(pasteboard.string(forType: .string) == "persistent")
        #expect(
            pasteboard.data(
                forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) == nil
        )
    }
}
#endif
