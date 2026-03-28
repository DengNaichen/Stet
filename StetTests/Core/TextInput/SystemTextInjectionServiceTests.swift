#if os(macOS)
    import AppKit
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("System Text Injection Service", .serialized)
    struct SystemTextInjectionServiceTests {
        @Test func pasteCapturesVerificationSnapshotAfterTargetActivation() async throws {
            let service = SystemTextInjectionService(clipboardService: TestClipboardService())
            let targetApplication = try #require(Self.activationCandidateApplication())
            let beforePaste = Self.makeSnapshot(
                value: "before",
                selectionLocation: 6,
                numberOfCharacters: 6
            )
            let afterPaste = Self.makeSnapshot(
                value: "before hello",
                selectionLocation: 12,
                numberOfCharacters: 12
            )
            var didActivateTarget = false
            var snapshotSequence = [beforePaste, afterPaste]

            let outcome = await service.performPasteClipboard(
                into: targetApplication,
                accessState: .init(hasAccessibilityAccess: true, hasPostEventAccess: true),
                activateApplication: { _ in
                    didActivateTarget = true
                },
                snapshotProvider: {
                    guard didActivateTarget else { return nil }
                    guard !snapshotSequence.isEmpty else { return afterPaste }
                    return snapshotSequence.removeFirst()
                },
                simulatePasteCommand: { true },
                sleep: { _ in },
                activationDelay: .milliseconds(0),
                prePasteDelay: .milliseconds(0),
                verificationPollInterval: .milliseconds(0),
                verificationAttempts: 1
            )

            #expect(outcome == .verifiedSuccess)
        }

        @Test func pasteVerificationRetriesBeforeFailing() async {
            let service = SystemTextInjectionService(clipboardService: TestClipboardService())
            let beforePaste = Self.makeSnapshot(
                value: "before",
                selectionLocation: 6,
                numberOfCharacters: 6
            )
            let unchanged = beforePaste
            let mutated = Self.makeSnapshot(
                value: "before hello",
                selectionLocation: 12,
                numberOfCharacters: 12
            )
            var snapshots = [unchanged, unchanged, mutated]

            let outcome = await service.verifyPasteOutcome(
                comparedTo: beforePaste,
                snapshotProvider: {
                    guard !snapshots.isEmpty else { return mutated }
                    return snapshots.removeFirst()
                },
                sleep: { _ in },
                pollInterval: .milliseconds(0),
                attempts: 3
            )

            #expect(outcome == .verifiedSuccess)
        }

        private static func makeSnapshot(
            value: String?,
            selectionLocation: Int,
            numberOfCharacters: Int
        ) -> SystemTextInjectionService.FocusedElementSnapshot {
            .init(
                value: value,
                selectedText: nil,
                selectionRange: .init(location: selectionLocation, length: 0),
                numberOfCharacters: numberOfCharacters
            )
        }

        private static func activationCandidateApplication() -> NSRunningApplication? {
            NSWorkspace.shared.runningApplications.first {
                !$0.isTerminated && $0.bundleIdentifier != Bundle.main.bundleIdentifier
            }
        }
    }
#endif
