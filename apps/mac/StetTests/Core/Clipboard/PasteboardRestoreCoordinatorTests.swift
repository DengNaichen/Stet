#if os(macOS)
    import AppKit
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Pasteboard Restore Coordinator", .serialized)
    struct PasteboardRestoreCoordinatorTests {
        private let restorationTimeout: Duration = .seconds(2)

        private func makePasteboard() -> NSPasteboard {
            NSPasteboard(name: NSPasteboard.Name("StetTests.\(UUID().uuidString)"))
        }

        private func restoresOriginalClipboardEventually(_ pasteboard: NSPasteboard) async -> Bool {
            await TestSupport.eventually(timeout: restorationTimeout) {
                pasteboard.string(forType: .string) == "original"
            }
        }

        @Test func rapidSuccessiveOverridesRestoreOriginalClipboard() async {
            let pasteboard = makePasteboard()
            let clipboard = SystemClipboardService(pasteboard: pasteboard)
            let coordinator = PasteboardRestoreCoordinator(restoreDelay: .milliseconds(40))

            pasteboard.clearContents()
            pasteboard.setString("original", forType: .string)

            coordinator.prepareForTemporaryOverride(on: pasteboard)
            clipboard.copy("first")
            coordinator.scheduleRestoreIfNeeded(on: pasteboard)

            coordinator.prepareForTemporaryOverride(on: pasteboard)
            clipboard.copy("second")
            coordinator.scheduleRestoreIfNeeded(on: pasteboard)

            #expect(await restoresOriginalClipboardEventually(pasteboard))
        }

        @Test func userClipboardChangesAreNotOverwrittenByDelayedRestore() async {
            let pasteboard = makePasteboard()
            let clipboard = SystemClipboardService(pasteboard: pasteboard)
            let coordinator = PasteboardRestoreCoordinator(restoreDelay: .milliseconds(40))

            pasteboard.clearContents()
            pasteboard.setString("original", forType: .string)

            coordinator.prepareForTemporaryOverride(on: pasteboard)
            clipboard.copy("temporary")
            coordinator.scheduleRestoreIfNeeded(on: pasteboard)

            clipboard.copy("user-copy")

            try? await Task.sleep(for: .milliseconds(80))

            #expect(pasteboard.string(forType: .string) == "user-copy")
        }

        @Test func discardPendingRestoreKeepsLatestClipboardValue() async {
            let pasteboard = makePasteboard()
            let clipboard = SystemClipboardService(pasteboard: pasteboard)
            let coordinator = PasteboardRestoreCoordinator(restoreDelay: .milliseconds(40))

            pasteboard.clearContents()
            pasteboard.setString("original", forType: .string)

            coordinator.prepareForTemporaryOverride(on: pasteboard)
            clipboard.copy("temporary")
            coordinator.scheduleRestoreIfNeeded(on: pasteboard)

            coordinator.discardPendingRestore()
            clipboard.copy("final")

            try? await Task.sleep(for: .milliseconds(80))

            #expect(pasteboard.string(forType: .string) == "final")
        }

        @Test func restoringSameTemporaryContentsDoesNotCancelDelayedRestore() async {
            let pasteboard = makePasteboard()
            let clipboard = SystemClipboardService(pasteboard: pasteboard)
            let coordinator = PasteboardRestoreCoordinator(restoreDelay: .milliseconds(40))

            pasteboard.clearContents()
            pasteboard.setString("original", forType: .string)

            coordinator.prepareForTemporaryOverride(on: pasteboard)
            clipboard.copy("temporary", transient: true)
            coordinator.scheduleRestoreIfNeeded(on: pasteboard)

            let temporarySnapshot = PasteboardSnapshot.capture(from: pasteboard)
            temporarySnapshot.restore(to: pasteboard)

            #expect(await restoresOriginalClipboardEventually(pasteboard))
        }
    }
#endif
