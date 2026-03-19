import Foundation

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
protocol ClipboardService {
    func copy(_ text: String)
}

@MainActor
final class SystemClipboardService: ClipboardService {
    #if os(macOS)
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }
    #endif

    func copy(_ text: String) {
        #if os(macOS)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}
