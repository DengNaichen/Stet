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
            window.contentView = NSHostingView(rootView: Editor(draft: draft))
            window.orderFront(nil)
            defer {
                if let sheet = window.attachedSheet { window.endSheet(sheet) }
                window.contentView = nil
                window.close()
            }

            settle()
            let sheet = try XCTUnwrap(window.attachedSheet)
            XCTAssertEqual(draft.buttonEnabled, false)

            draft.text = "OpenAI"
            settle()
            XCTAssertEqual(draft.buttonEnabled, true, "Valid input must enable Add in the open sheet")
            XCTAssertTrue(window.attachedSheet === sheet)

            draft.text = "沙发上"
            settle()
            XCTAssertEqual(draft.buttonEnabled, true)

            draft.text = ""
            settle()
            XCTAssertEqual(draft.buttonEnabled, false, "Clearing input must disable Add again")
        }

        private func settle() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
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
