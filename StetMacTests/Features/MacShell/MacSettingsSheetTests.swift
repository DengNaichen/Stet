#if os(macOS)
    import AppKit
    import Combine
    import SwiftUI
    import XCTest

    @testable import Stet

    @MainActor
    final class MacSettingsSheetTests: XCTestCase {
        func testPresentedSheetRefreshesValidationWhenParentDraftChanges() throws {
            let draft = Draft()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: Editor(draft: draft))
            // Exercise presentation requested before SwiftUI's host has a window.
            _ = host.fittingSize
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            window.contentView = host
            window.orderFront(nil)
            defer {
                if let sheet = window.attachedSheet { window.endSheet(sheet) }
                window.contentView = nil
                window.close()
            }

            waitUntil { window.attachedSheet != nil && draft.buttonEnabled == false }
            let sheet = try XCTUnwrap(window.attachedSheet)
            XCTAssertEqual(draft.buttonEnabled, false)

            draft.text = "OpenAI"
            waitUntil { draft.buttonEnabled == true }
            XCTAssertEqual(draft.buttonEnabled, true, "Valid input must enable Add in the open sheet")
            XCTAssertTrue(window.attachedSheet === sheet)

            draft.text = "沙发上"
            waitUntil { draft.buttonEnabled == true }
            XCTAssertEqual(draft.buttonEnabled, true)

            draft.text = ""
            waitUntil { draft.buttonEnabled == false }
            XCTAssertEqual(draft.buttonEnabled, false, "Clearing input must disable Add again")
        }

        private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
            let deadline = Date().addingTimeInterval(5)
            while !condition(), Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            XCTAssertTrue(condition(), "Timed out waiting for sheet state", file: file, line: line)
        }

        private final class Draft: ObservableObject {
            @Published var text = ""
            var buttonEnabled: Bool?
        }

        private struct Editor: View {
            @ObservedObject var draft: Draft
            @State private var isPresented = true

            var body: some View {
                Text("Dictionary").frame(width: 300, height: 200)
                    .macSettingsSheet(isPresented: $isPresented) {
                        VStack {
                            TextField("Words", text: $draft.text)
                            Button("Add Words") {}
                                .background(EnabledProbe(draft: draft))
                                .disabled(draft.text.isEmpty)
                        }
                        .frame(width: 250, height: 100)
                    }
            }
        }

        private struct EnabledProbe: NSViewRepresentable {
            @Environment(\.isEnabled) private var isEnabled
            let draft: Draft

            func makeNSView(context: Context) -> NSView { NSView() }

            func updateNSView(_ view: NSView, context: Context) {
                draft.buttonEnabled = isEnabled
            }
        }
    }
#endif
