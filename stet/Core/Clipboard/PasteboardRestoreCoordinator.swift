#if os(macOS)
    import AppKit
    import Foundation

    @MainActor
    final class PasteboardRestoreCoordinator {
        private let restoreDelay: Duration
        private var pendingRestoreTask: Task<Void, Never>?
        private var pendingOriginalSnapshot: PasteboardSnapshot?

        init(restoreDelay: Duration = .milliseconds(800)) {
            self.restoreDelay = restoreDelay
        }

        deinit {
            pendingRestoreTask?.cancel()
        }

        func prepareForTemporaryOverride(on pasteboard: NSPasteboard) {
            let capturedFreshSnapshot = pendingOriginalSnapshot == nil
            if capturedFreshSnapshot {
                pendingOriginalSnapshot = PasteboardSnapshot.capture(from: pasteboard)
            }

            pendingRestoreTask?.cancel()
            pendingRestoreTask = nil
            emitPasteboardTrace(
                stage: "prepare",
                pasteboard: pasteboard,
                details:
                    "capturedFreshSnapshot=\(capturedFreshSnapshot) originalItemCount=\(pendingOriginalSnapshot?.itemCount ?? 0)"
            )
        }

        func scheduleRestoreIfNeeded(on pasteboard: NSPasteboard) {
            scheduleRestoreIfNeeded(on: pasteboard, delayOverride: nil)
        }

        func scheduleRestoreIfNeeded(
            on pasteboard: NSPasteboard,
            delayOverride: Duration?
        ) {
            guard let snapshot = pendingOriginalSnapshot else {
                emitPasteboardTrace(
                    stage: "schedule_restore_skipped",
                    pasteboard: pasteboard,
                    details: "reason=no_pending_original_snapshot"
                )
                return
            }

            let effectiveDelay = delayOverride ?? restoreDelay
            let temporarySnapshot = PasteboardSnapshot.capture(from: pasteboard)
            emitPasteboardTrace(
                stage: "schedule_restore",
                pasteboard: pasteboard,
                details:
                    "delayMs=\(durationMilliseconds(effectiveDelay)) originalItemCount=\(snapshot.itemCount) temporaryItemCount=\(temporarySnapshot.itemCount)"
            )
            pendingRestoreTask?.cancel()
            pendingRestoreTask = Task { @MainActor [weak self] in
                guard let self else { return }

                try? await Task.sleep(for: effectiveDelay)
                guard !Task.isCancelled else { return }

                defer {
                    pendingRestoreTask = nil
                    pendingOriginalSnapshot = nil
                }

                guard temporarySnapshot.matches(pasteboard) else {
                    AppLogger.info(
                        "Pasteboard restore skipped: temporary snapshot no longer matches current pasteboard",
                        category: .dictation
                    )
                    emitPasteboardTrace(
                        stage: "restore_skipped_mismatch",
                        pasteboard: pasteboard,
                        details:
                            "temporaryItemCount=\(temporarySnapshot.itemCount) currentItemCount=\(PasteboardSnapshot.capture(from: pasteboard).itemCount)"
                    )
                    return
                }

                snapshot.restore(to: pasteboard)
                emitPasteboardTrace(
                    stage: "restore_applied",
                    pasteboard: pasteboard,
                    details: "restoredItemCount=\(snapshot.itemCount)"
                )
            }
        }

        func restoreImmediatelyIfNeeded(on pasteboard: NSPasteboard) {
            guard let snapshot = pendingOriginalSnapshot else {
                emitPasteboardTrace(
                    stage: "restore_immediate_skipped",
                    pasteboard: pasteboard,
                    details: "reason=no_pending_original_snapshot"
                )
                return
            }

            pendingRestoreTask?.cancel()
            pendingRestoreTask = nil
            pendingOriginalSnapshot = nil
            snapshot.restore(to: pasteboard)
            emitPasteboardTrace(
                stage: "restore_immediate",
                pasteboard: pasteboard,
                details: "restoredItemCount=\(snapshot.itemCount)"
            )
        }

        func discardPendingRestore() {
            pendingRestoreTask?.cancel()
            pendingRestoreTask = nil
            pendingOriginalSnapshot = nil
            AppLogger.info(
                "PasteboardTrace stage=discard_pending",
                category: .perfTrace
            )
        }

        private func emitPasteboardTrace(
            stage: String,
            pasteboard: NSPasteboard,
            details: String? = nil
        ) {
            let detailsSuffix = details.map { " \($0)" } ?? ""
            AppLogger.info(
                "PasteboardTrace stage=\(stage) changeCount=\(pasteboard.changeCount) pendingOriginalSnapshot=\(pendingOriginalSnapshot != nil)\(detailsSuffix)",
                category: .perfTrace
            )
        }

        private func durationMilliseconds(_ duration: Duration) -> String {
            let components = duration.components
            let milliseconds =
                (Double(components.seconds) * 1_000)
                + (Double(components.attoseconds) / 1_000_000_000_000_000)
            return String(format: "%.1f", milliseconds)
        }
    }

    struct PasteboardSnapshot {
        private let items: [[NSPasteboard.PasteboardType: Data]]

        var itemCount: Int {
            items.count
        }

        static func capture(from pasteboard: NSPasteboard) -> Self {
            let items = (pasteboard.pasteboardItems ?? []).map { item in
                var payload: [NSPasteboard.PasteboardType: Data] = [:]

                for type in item.types {
                    if let data = item.data(forType: type) {
                        payload[type] = data
                    }
                }

                return payload
            }

            return Self(items: items)
        }

        func matches(_ pasteboard: NSPasteboard) -> Bool {
            Self.capture(from: pasteboard).items == items
        }

        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()

            let restoredItems = items.compactMap { payload -> NSPasteboardItem? in
                let item = NSPasteboardItem()
                var hasContent = false

                for (type, data) in payload {
                    if item.setData(data, forType: type) {
                        hasContent = true
                    }
                }

                return hasContent ? item : nil
            }

            if !restoredItems.isEmpty {
                let success = pasteboard.writeObjects(restoredItems)
                if !success {
                    AppLogger.warning(
                        "Pasteboard restore failed: unable to write restored items to pasteboard",
                        category: .dictation
                    )
                }
            } else if !items.isEmpty {
                AppLogger.warning(
                    "Pasteboard restore failed: no items could be restored from snapshot",
                    category: .dictation
                )
            }
        }
    }
#endif
