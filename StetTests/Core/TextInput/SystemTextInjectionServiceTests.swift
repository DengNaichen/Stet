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

        @Test func pasteReturnsTextInputUnavailableWhenBaselineWasVerifiableButFollowUpsWereOpaque()
            async
        {
            let service = SystemTextInjectionService(clipboardService: TestClipboardService())
            let beforePaste = Self.makeSnapshot(
                value: "before",
                selectionLocation: 6,
                numberOfCharacters: 6
            )

            let outcome = await service.verifyPasteOutcome(
                comparedTo: beforePaste,
                snapshotProvider: { nil },
                sleep: { _ in },
                pollInterval: .milliseconds(0),
                attempts: 2
            )

            #expect(outcome == .eventPostedVerificationUnavailableInTextInput)
        }

        @Test func pasteWaitsForVerifiableBaselineBeforeDeclaringVerificationUnavailable() async {
            let service = SystemTextInjectionService(clipboardService: TestClipboardService())
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
            var didSimulatePaste = false
            var prePasteSnapshots: [SystemTextInjectionService.FocusedElementSnapshot?] = [
                nil,
                nil,
                beforePaste,
            ]
            var postPasteSnapshots: [SystemTextInjectionService.FocusedElementSnapshot?] = [
                afterPaste
            ]

            let outcome = await service.performPasteClipboard(
                into: nil,
                accessState: .init(hasAccessibilityAccess: true, hasPostEventAccess: true),
                activateApplication: { _ in },
                snapshotProvider: {
                    if didSimulatePaste {
                        guard !postPasteSnapshots.isEmpty else { return afterPaste }
                        return postPasteSnapshots.removeFirst()
                    }

                    guard !prePasteSnapshots.isEmpty else { return beforePaste }
                    return prePasteSnapshots.removeFirst()
                },
                simulatePasteCommand: {
                    didSimulatePaste = true
                    return true
                },
                sleep: { _ in },
                activationDelay: .milliseconds(0),
                prePasteDelay: .milliseconds(0),
                verificationBaselinePollInterval: .milliseconds(0),
                verificationBaselineAttempts: 3,
                verificationPollInterval: .milliseconds(0),
                verificationAttempts: 1
            )

            #expect(outcome == .verifiedSuccess)
        }

        @Test func pasteTreatsEditableButUnverifiableBaselineAsTextInputContext() async {
            let service = SystemTextInjectionService(clipboardService: TestClipboardService())
            let likelyTextInput = Self.makeSnapshot(
                value: nil,
                selectionLocation: nil,
                numberOfCharacters: nil,
                role: "AXWebArea",
                isEditable: true
            )

            let outcome = await service.performPasteClipboard(
                into: nil,
                accessState: .init(hasAccessibilityAccess: true, hasPostEventAccess: true),
                activateApplication: { _ in },
                snapshotProvider: { likelyTextInput },
                simulatePasteCommand: { true },
                sleep: { _ in },
                activationDelay: .milliseconds(0),
                prePasteDelay: .milliseconds(0),
                verificationBaselinePollInterval: .milliseconds(0),
                verificationBaselineAttempts: 1,
                verificationPollInterval: .milliseconds(0),
                verificationAttempts: 1
            )

            #expect(outcome == .eventPostedVerificationUnavailableInTextInput)
        }

        @Test func pasteKeepsGenericUnavailableWhenBaselineHasNoTextInputSignal() async {
            let service = SystemTextInjectionService(clipboardService: TestClipboardService())
            let unknownFocusedElement = Self.makeSnapshot(
                value: nil,
                selectionLocation: nil,
                numberOfCharacters: nil,
                role: "AXGroup",
                isEditable: false
            )

            let outcome = await service.performPasteClipboard(
                into: nil,
                accessState: .init(hasAccessibilityAccess: true, hasPostEventAccess: true),
                activateApplication: { _ in },
                snapshotProvider: { unknownFocusedElement },
                simulatePasteCommand: { true },
                sleep: { _ in },
                activationDelay: .milliseconds(0),
                prePasteDelay: .milliseconds(0),
                verificationBaselinePollInterval: .milliseconds(0),
                verificationBaselineAttempts: 1,
                verificationPollInterval: .milliseconds(0),
                verificationAttempts: 1
            )

            #expect(outcome == .eventPostedVerificationUnavailable)
        }

        private static func makeSnapshot(
            value: String?,
            selectionLocation: Int?,
            numberOfCharacters: Int?,
            role: String? = nil,
            isEditable: Bool? = nil
        ) -> SystemTextInjectionService.FocusedElementSnapshot {
            .init(
                value: value,
                selectedText: nil,
                selectionRange: selectionLocation.map { .init(location: $0, length: 0) },
                numberOfCharacters: numberOfCharacters,
                role: role,
                isEditable: isEditable
            )
        }

        private static func activationCandidateApplication() -> NSRunningApplication? {
            NSWorkspace.shared.runningApplications.first {
                !$0.isTerminated && $0.bundleIdentifier != Bundle.main.bundleIdentifier
            }
        }
    }
#endif
