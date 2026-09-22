import AppKit

@MainActor
enum ClipboardWriter {
    static func writeText(_ text: String, to pasteboard: NSPasteboard) -> Bool {
        replaceContents(of: pasteboard) { pasteboard.setString(text, forType: .string) }
    }

    static func writePNG(_ data: Data, to pasteboard: NSPasteboard) -> Bool {
        replaceContents(of: pasteboard) { pasteboard.setData(data, forType: .png) }
    }

    /// The closure is an internal seam for failed-write tests on private pasteboards.
    static func replaceContents(of pasteboard: NSPasteboard, using write: () -> Bool) -> Bool {
        let permitted: Bool
        if pasteboard.name != .general {
            permitted = true
        } else if #available(macOS 15.4, *) {
            permitted = shouldSnapshot(isGeneral: true, accessBehavior: pasteboard.accessBehavior)
        } else {
            permitted = false
        }
        return replaceContents(of: pasteboard, snapshotPermitted: permitted,
                               takeSnapshot: { snapshot(pasteboard) }, using: write)
    }

    @available(macOS 15.4, *)
    static func shouldSnapshot(isGeneral: Bool, accessBehavior: NSPasteboard.AccessBehavior?) -> Bool {
        !isGeneral || accessBehavior == .alwaysAllow
    }

    /// Keep the read behind the policy gate: even fetching items may prompt on macOS.
    static func replaceContents(of pasteboard: NSPasteboard, snapshotPermitted: Bool,
                                takeSnapshot: () -> [NSPasteboardItem]?, using write: () -> Bool) -> Bool {
        guard snapshotPermitted else {
            pasteboard.clearContents()
            return write()
        }
        let originalRevision = pasteboard.changeCount
        guard let originalItems = takeSnapshot(),
              pasteboard.changeCount == originalRevision else { return false }

        let ownedRevision = pasteboard.clearContents()
        if write() { return true }

        // Another application may have replaced the clipboard during the attempt.
        // AppKit offers no cross-process transaction, so recovery is best effort.
        guard pasteboard.changeCount == ownedRevision else { return false }
        pasteboard.clearContents()
        if !originalItems.isEmpty { _ = pasteboard.writeObjects(originalItems) }
        return false
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem]? {
        let items = pasteboard.pasteboardItems ?? []
        // Do not discard legacy representations if AppKit cannot expose their items.
        guard !items.isEmpty || (pasteboard.types ?? []).isEmpty else { return nil }
        var copies: [NSPasteboardItem] = []
        for item in items {
            let copy = NSPasteboardItem()
            for type in item.types {
                // Materialize every representation before replacing its owner.
                guard let data = item.data(forType: type), copy.setData(data, forType: type) else { return nil }
            }
            copies.append(copy)
        }
        return copies
    }
}
