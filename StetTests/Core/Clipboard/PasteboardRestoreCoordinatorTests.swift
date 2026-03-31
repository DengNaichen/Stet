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

        @Test func delayOverrideKeepsTemporaryClipboardUntilOverrideExpires() async {
            let pasteboard = makePasteboard()
            let clipboard = SystemClipboardService(pasteboard: pasteboard)
            let coordinator = PasteboardRestoreCoordinator(restoreDelay: .milliseconds(40))

            pasteboard.clearContents()
            pasteboard.setString("original", forType: .string)

            coordinator.prepareForTemporaryOverride(on: pasteboard)
            clipboard.copy("temporary")
            coordinator.scheduleRestoreIfNeeded(
                on: pasteboard,
                delayOverride: .milliseconds(120)
            )

            try? await Task.sleep(for: .milliseconds(70))
            #expect(pasteboard.string(forType: .string) == "temporary")
            #expect(await restoresOriginalClipboardEventually(pasteboard))
        }

        @Test func delayOverrideStillSkipsRestoreAfterExternalClipboardChange() async {
            let pasteboard = makePasteboard()
            let clipboard = SystemClipboardService(pasteboard: pasteboard)
            let coordinator = PasteboardRestoreCoordinator(restoreDelay: .milliseconds(40))

            pasteboard.clearContents()
            pasteboard.setString("original", forType: .string)

            coordinator.prepareForTemporaryOverride(on: pasteboard)
            clipboard.copy("temporary")
            coordinator.scheduleRestoreIfNeeded(
                on: pasteboard,
                delayOverride: .milliseconds(120)
            )

            try? await Task.sleep(for: .milliseconds(60))
            clipboard.copy("user-copy")

            try? await Task.sleep(for: .milliseconds(100))

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

        @Test func restoreSkippedWhenClipboardChangesExternally() async {
            let pasteboard = makePasteboard()
            let clipboard = SystemClipboardService(pasteboard: pasteboard)
            let coordinator = PasteboardRestoreCoordinator(restoreDelay: .milliseconds(40))

            pasteboard.clearContents()
            pasteboard.setString("original", forType: .string)

            coordinator.prepareForTemporaryOverride(on: pasteboard)
            clipboard.copy("temporary")
            coordinator.scheduleRestoreIfNeeded(on: pasteboard)

            pasteboard.clearContents()
            pasteboard.setString("external-change", forType: .string)

            try? await Task.sleep(for: .milliseconds(80))

            #expect(pasteboard.string(forType: .string) == "external-change")
        }

        @Test func restorePreservesMultiItemPayloads() async {
            let pasteboard = makePasteboard()
            let coordinator = PasteboardRestoreCoordinator(restoreDelay: .milliseconds(40))

            pasteboard.clearContents()
            let item1 = NSPasteboardItem()
            item1.setString("text1", forType: .string)
            item1.setString("https://example.com", forType: .URL)

            let item2 = NSPasteboardItem()
            item2.setString("text2", forType: .string)

            pasteboard.writeObjects([item1, item2])
            #expect((pasteboard.pasteboardItems ?? []).count == 2)

            coordinator.prepareForTemporaryOverride(on: pasteboard)
            pasteboard.clearContents()
            pasteboard.setString("temporary", forType: .string)
            coordinator.scheduleRestoreIfNeeded(on: pasteboard)

            #expect(
                await TestSupport.eventually(timeout: restorationTimeout) {
                    let items = pasteboard.pasteboardItems ?? []
                    return items.count == 2
                        && items[0].string(forType: .string) == "text1"
                        && items[0].string(forType: .URL) == "https://example.com"
                        && items[1].string(forType: .string) == "text2"
                })
        }

        @Test func immediateRestoreOnFailureClearsPendingState() async {
            let pasteboard = makePasteboard()
            let clipboard = SystemClipboardService(pasteboard: pasteboard)
            let coordinator = PasteboardRestoreCoordinator(restoreDelay: .milliseconds(40))

            pasteboard.clearContents()
            pasteboard.setString("original", forType: .string)

            coordinator.prepareForTemporaryOverride(on: pasteboard)
            clipboard.copy("temporary")
            coordinator.scheduleRestoreIfNeeded(on: pasteboard)

            coordinator.restoreImmediatelyIfNeeded(on: pasteboard)

            #expect(pasteboard.string(forType: .string) == "original")

            clipboard.copy("after-immediate-restore")
            try? await Task.sleep(for: .milliseconds(80))

            #expect(pasteboard.string(forType: .string) == "after-immediate-restore")
        }

        @Test func restoreHandlesEmptyClipboardGracefully() async {
            let pasteboard = makePasteboard()
            let clipboard = SystemClipboardService(pasteboard: pasteboard)
            let coordinator = PasteboardRestoreCoordinator(restoreDelay: .milliseconds(40))

            pasteboard.clearContents()

            coordinator.prepareForTemporaryOverride(on: pasteboard)
            clipboard.copy("temporary")
            coordinator.scheduleRestoreIfNeeded(on: pasteboard)

            try? await Task.sleep(for: .milliseconds(80))

            #expect(pasteboard.string(forType: .string) == nil)
            #expect((pasteboard.pasteboardItems ?? []).isEmpty)
        }

        @Test func multiplePrepareCallsPreserveFirstSnapshot() async {
            let pasteboard = makePasteboard()
            let clipboard = SystemClipboardService(pasteboard: pasteboard)
            let coordinator = PasteboardRestoreCoordinator(restoreDelay: .milliseconds(40))

            pasteboard.clearContents()
            pasteboard.setString("original", forType: .string)

            coordinator.prepareForTemporaryOverride(on: pasteboard)
            clipboard.copy("first-temporary")

            coordinator.prepareForTemporaryOverride(on: pasteboard)
            clipboard.copy("second-temporary")
            coordinator.scheduleRestoreIfNeeded(on: pasteboard)

            #expect(await restoresOriginalClipboardEventually(pasteboard))
        }
    }
#endif
