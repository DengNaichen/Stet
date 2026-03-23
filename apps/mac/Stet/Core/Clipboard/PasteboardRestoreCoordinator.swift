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
        if pendingOriginalSnapshot == nil {
            pendingOriginalSnapshot = PasteboardSnapshot.capture(from: pasteboard)
        }

        pendingRestoreTask?.cancel()
        pendingRestoreTask = nil
    }

    func scheduleRestoreIfNeeded(on pasteboard: NSPasteboard) {
        guard let snapshot = pendingOriginalSnapshot else { return }

        let temporarySnapshot = PasteboardSnapshot.capture(from: pasteboard)
        pendingRestoreTask?.cancel()
        pendingRestoreTask = Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(for: self.restoreDelay)
            guard !Task.isCancelled else { return }

            defer {
                pendingRestoreTask = nil
                pendingOriginalSnapshot = nil
            }

            guard temporarySnapshot.matches(pasteboard) else {
                return
            }

            snapshot.restore(to: pasteboard)
        }
    }

    func restoreImmediatelyIfNeeded(on pasteboard: NSPasteboard) {
        guard let snapshot = pendingOriginalSnapshot else { return }

        pendingRestoreTask?.cancel()
        pendingRestoreTask = nil
        pendingOriginalSnapshot = nil
        snapshot.restore(to: pasteboard)
    }

    func discardPendingRestore() {
        pendingRestoreTask?.cancel()
        pendingRestoreTask = nil
        pendingOriginalSnapshot = nil
    }
}

struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

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
            pasteboard.writeObjects(restoredItems)
        }
    }
}
#endif
