#if os(macOS)
    import AppKit
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Pasteboard Restore Coordinator", .serialized)
    struct PasteboardRestoreCoordinatorTests {
        @MainActor
        private struct Subject {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("StetTests.\(UUID().uuidString)"))
            let clock = TestClock()
            let clipboard: SystemClipboardService
            let coordinator: PasteboardRestoreCoordinator

            init(initialText: String? = "original") {
                clipboard = SystemClipboardService(pasteboard: pasteboard)
                let clock = clock
                coordinator = PasteboardRestoreCoordinator(
                    restoreDelay: .milliseconds(40), sleep: { try await clock.sleep(for: $0) })
                pasteboard.clearContents()
                if let initialText { pasteboard.setString(initialText, forType: .string) }
            }

            func override(with text: String = "temporary") -> Task<Void, Never>? {
                coordinator.prepareForTemporaryOverride(on: pasteboard)
                clipboard.copy(text)
                return coordinator.scheduleRestoreIfNeeded(on: pasteboard)
            }

            func finish(_ task: Task<Void, Never>?) async throws {
                let task = try #require(task)
                let delay = await clock.nextSleep()
                #expect(delay == .milliseconds(40))
                await clock.advance(by: delay)
                await task.value
            }
        }

        @Test func rapidSuccessiveOverridesRestoreOriginalClipboard() async throws {
            let subject = Subject()
            let first = subject.override(with: "first")
            _ = await subject.clock.nextSleep()
            let second = subject.override(with: "second")
            try await subject.finish(second)
            await first?.value
            #expect(subject.pasteboard.string(forType: .string) == "original")
        }

        @Test func userClipboardChangesAreNotOverwrittenByDelayedRestore() async throws {
            let subject = Subject()
            let task = subject.override()
            subject.clipboard.copy("user-copy")
            try await subject.finish(task)
            #expect(subject.pasteboard.string(forType: .string) == "user-copy")
        }

        @Test func delayOverrideKeepsTemporaryClipboardUntilOverrideExpires() async throws {
            let subject = Subject()
            subject.coordinator.prepareForTemporaryOverride(on: subject.pasteboard)
            subject.clipboard.copy("temporary")
            let task = try #require(
                subject.coordinator.scheduleRestoreIfNeeded(
                    on: subject.pasteboard, delayOverride: .milliseconds(120)))
            #expect(await subject.clock.nextSleep() == .milliseconds(120))
            await subject.clock.advance(by: .milliseconds(70))
            #expect(subject.pasteboard.string(forType: .string) == "temporary")
            await subject.clock.advance(by: .milliseconds(50))
            await task.value
            #expect(subject.pasteboard.string(forType: .string) == "original")
        }

        @Test func delayOverrideStillSkipsRestoreAfterExternalClipboardChange() async throws {
            let subject = Subject()
            subject.coordinator.prepareForTemporaryOverride(on: subject.pasteboard)
            subject.clipboard.copy("temporary")
            let task = try #require(
                subject.coordinator.scheduleRestoreIfNeeded(
                    on: subject.pasteboard, delayOverride: .milliseconds(120)))
            #expect(await subject.clock.nextSleep() == .milliseconds(120))
            await subject.clock.advance(by: .milliseconds(60))
            subject.clipboard.copy("user-copy")
            await subject.clock.advance(by: .milliseconds(60))
            await task.value
            #expect(subject.pasteboard.string(forType: .string) == "user-copy")
        }

        @Test func discardPendingRestoreKeepsLatestClipboardValue() async throws {
            let subject = Subject()
            let task = try #require(subject.override())
            _ = await subject.clock.nextSleep()
            subject.coordinator.discardPendingRestore()
            subject.clipboard.copy("final")
            await task.value
            await subject.clock.advance(by: .seconds(1))
            #expect(task.isCancelled)
            #expect(subject.pasteboard.string(forType: .string) == "final")
        }

        @Test func restoringSameTemporaryContentsDoesNotCancelDelayedRestore() async throws {
            let subject = Subject()
            subject.coordinator.prepareForTemporaryOverride(on: subject.pasteboard)
            subject.clipboard.copy("temporary", transient: true)
            let task = subject.coordinator.scheduleRestoreIfNeeded(on: subject.pasteboard)
            let snapshot = PasteboardSnapshot.capture(from: subject.pasteboard)
            snapshot.restore(to: subject.pasteboard)
            try await subject.finish(task)
            #expect(subject.pasteboard.string(forType: .string) == "original")
        }

        @Test func restoreSkippedWhenClipboardChangesExternally() async throws {
            let subject = Subject()
            let task = subject.override()
            subject.pasteboard.clearContents()
            subject.pasteboard.setString("external-change", forType: .string)
            try await subject.finish(task)
            #expect(subject.pasteboard.string(forType: .string) == "external-change")
        }

        @Test func restorePreservesMultiItemPayloads() async throws {
            let subject = Subject(initialText: nil)
            let first = NSPasteboardItem()
            first.setString("text1", forType: .string)
            first.setString("https://example.com", forType: .URL)
            let second = NSPasteboardItem()
            second.setString("text2", forType: .string)
            subject.pasteboard.writeObjects([first, second])
            #expect((subject.pasteboard.pasteboardItems ?? []).count == 2)
            let task = subject.override()
            try await subject.finish(task)
            let items = try #require(subject.pasteboard.pasteboardItems)
            try #require(items.count == 2)
            #expect(items[0].string(forType: .string) == "text1")
            #expect(items[0].string(forType: .URL) == "https://example.com")
            #expect(items[1].string(forType: .string) == "text2")
        }

        @Test func immediateRestoreOnFailureClearsPendingState() async throws {
            let subject = Subject()
            let task = try #require(subject.override())
            _ = await subject.clock.nextSleep()
            subject.coordinator.restoreImmediatelyIfNeeded(on: subject.pasteboard)
            #expect(subject.pasteboard.string(forType: .string) == "original")
            subject.clipboard.copy("after-immediate-restore")
            await task.value
            await subject.clock.advance(by: .seconds(1))
            #expect(task.isCancelled)
            #expect(subject.pasteboard.string(forType: .string) == "after-immediate-restore")
        }

        @Test func restoreHandlesEmptyClipboardGracefully() async throws {
            let subject = Subject(initialText: nil)
            let task = subject.override()
            try await subject.finish(task)
            #expect(subject.pasteboard.string(forType: .string) == nil)
            #expect((subject.pasteboard.pasteboardItems ?? []).isEmpty)
        }

        @Test func multiplePrepareCallsPreserveFirstSnapshot() async throws {
            let subject = Subject()
            subject.coordinator.prepareForTemporaryOverride(on: subject.pasteboard)
            subject.clipboard.copy("first-temporary")
            subject.coordinator.prepareForTemporaryOverride(on: subject.pasteboard)
            subject.clipboard.copy("second-temporary")
            let task = subject.coordinator.scheduleRestoreIfNeeded(on: subject.pasteboard)
            try await subject.finish(task)
            #expect(subject.pasteboard.string(forType: .string) == "original")
        }
    }
#endif
