import Foundation

#if os(macOS)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

@MainActor
protocol ClipboardService {
    func copy(_ text: String, transient: Bool)
}

extension ClipboardService {
    func copy(_ text: String) {
        copy(text, transient: false)
    }
}

@MainActor
final class SystemClipboardService: ClipboardService {
    #if os(macOS)
        private let pasteboard: NSPasteboard
        private static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")
        private static let transientType = NSPasteboard.PasteboardType(
            "org.nspasteboard.TransientType")

        init(pasteboard: NSPasteboard = .general) {
            self.pasteboard = pasteboard
        }
    #endif

    func copy(_ text: String, transient: Bool) {
        #if os(macOS)
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            if let bundleIdentifier = Bundle.main.bundleIdentifier {
                pasteboard.setString(bundleIdentifier, forType: Self.sourceType)
            }
            if transient {
                pasteboard.setData(Data(), forType: Self.transientType)
            }
        #elseif canImport(UIKit)
            UIPasteboard.general.string = text
        #endif
    }
}
