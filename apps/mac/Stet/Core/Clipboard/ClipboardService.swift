import Foundation

#if os(macOS)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

@MainActor
protocol ClipboardService {
    @discardableResult
    func copy(_ text: String, transient: Bool) -> Bool
}

extension ClipboardService {
    @discardableResult
    func copy(_ text: String) -> Bool {
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

    @discardableResult
    func copy(_ text: String, transient: Bool) -> Bool {
        #if os(macOS)
            do {
                pasteboard.clearContents()

                guard pasteboard.setString(text, forType: .string) else {
                    AppLogger.error(
                        "Failed to write text to clipboard (setString returned false)",
                        category: .general
                    )
                    return false
                }

                if let bundleIdentifier = Bundle.main.bundleIdentifier {
                    _ = pasteboard.setString(bundleIdentifier, forType: Self.sourceType)
                }
                if transient {
                    _ = pasteboard.setData(Data(), forType: Self.transientType)
                }

                return true
            } catch {
                AppLogger.error(
                    "Failed to write text to clipboard: \(error.localizedDescription)",
                    category: .general
                )
                return false
            }
        #elseif canImport(UIKit)
            UIPasteboard.general.string = text
            return true
        #endif
    }
}
