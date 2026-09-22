import AppKit
import Testing
@testable import SmartClipboard

@MainActor struct ClipboardWriterTests {
    private let customType = NSPasteboard.PasteboardType("app.smartclipboard.tests.custom")

    private func withPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try body(board)
    }

    private func item(_ representations: [(NSPasteboard.PasteboardType, Data)]) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        for (type, data) in representations { #expect(item.setData(data, forType: type)) }
        return item
    }

    private func contents(_ board: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (board.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    @Test func textWriteReplacesItemsWithInertPlainText() {
        withPasteboard { board in
            #expect(board.writeObjects([item([(.png, Data([1, 2, 3])), (customType, Data([4]))])]))
            let text = "<b>Keep this markup as text</b>"
            #expect(ClipboardWriter.writeText(text, to: board))
            #expect(board.string(forType: .string) == text)
            #expect(board.pasteboardItems?.count == 1)
            // AppKit can advertise legacy aliases; generated markup must stay inert.
            #expect((board.types ?? []).contains(.string))
            #expect(!(board.types ?? []).contains(.html))
            #expect(!(board.types ?? []).contains(.rtf))
            #expect(!(board.types ?? []).contains(.png))
            #expect(!(board.types ?? []).contains(customType))
        }
    }

    @Test func pngWriteReplacesTextWithExactImageBytes() {
        withPasteboard { board in
            #expect(board.setString("Previous private text", forType: .string))
            let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2])
            #expect(ClipboardWriter.writePNG(png, to: board))
            #expect(board.data(forType: .png) == png)
            // AppKit may also expose standard image aliases/conversions.
            #expect((board.types ?? []).contains(.png))
            #expect(!(board.types ?? []).contains(.string))
        }
    }

    @Test func failedWriteRestoresEveryItemAndRepresentation() {
        withPasteboard { board in
            #expect(board.writeObjects([
                item([(.string, Data("First item".utf8)), (.rtf, Data("{\\rtf1 First item}".utf8))]),
                item([(.png, Data([0, 1, 2, 255])), (customType, Data())]),
                item([(.string, Data("Third item".utf8)), (customType, Data([7, 8, 9]))])]))
            let original = contents(board)
            var attempts = 0
            let result = ClipboardWriter.replaceContents(of: board) {
                attempts += 1
                #expect((board.pasteboardItems ?? []).isEmpty)
                return false
            }
            #expect(!result)
            #expect(attempts == 1)
            #expect(contents(board) == original)
        }
    }

    @Test func failedWriteRemovesItsPartialContentsBeforeRestoring() {
        withPasteboard { board in
            #expect(board.writeObjects([item([(.string, Data("Original".utf8)), (customType, Data([5]))])]))
            let original = contents(board)
            let result = ClipboardWriter.replaceContents(of: board) {
                #expect(board.setData(Data([9]), forType: .png))
                return false
            }
            #expect(!result)
            #expect(contents(board) == original)
            #expect(board.data(forType: .png) == nil)
        }
    }

    @Test func failedWriteDoesNotOverwriteANewerClipboardOwner() {
        withPasteboard { board in
            #expect(board.setString("Original", forType: .string))
            var newer: [[NSPasteboard.PasteboardType: Data]] = []
            var newerRevision = 0
            let result = ClipboardWriter.replaceContents(of: board) {
                // Simulate another process claiming the pasteboard during the failed attempt.
                board.clearContents()
                #expect(board.writeObjects([item([(.string, Data("New owner".utf8)), (customType, Data([42]))])]))
                newer = contents(board)
                newerRevision = board.changeCount
                return false
            }
            #expect(!result)
            #expect(contents(board) == newer)
            #expect(board.changeCount == newerRevision)
        }
    }

    @Test func failedWriteToEmptyPasteboardLeavesItEmpty() {
        withPasteboard { board in
            board.clearContents()
            #expect(!ClipboardWriter.replaceContents(of: board) { false })
            #expect((board.pasteboardItems ?? []).isEmpty)
            #expect((board.types ?? []).isEmpty)
        }
    }

    @Test func generalClipboardSnapshotRequiresAlreadyAllowedAccess() {
        if #available(macOS 15.4, *) {
            for access in [NSPasteboard.AccessBehavior.default, .ask, .alwaysDeny] {
                #expect(!ClipboardWriter.shouldSnapshot(isGeneral: true, accessBehavior: access))
                #expect(ClipboardWriter.shouldSnapshot(isGeneral: false, accessBehavior: access))
            }
            #expect(ClipboardWriter.shouldSnapshot(isGeneral: true, accessBehavior: .alwaysAllow))
            #expect(ClipboardWriter.shouldSnapshot(isGeneral: false, accessBehavior: .alwaysAllow))
            #expect(!ClipboardWriter.shouldSnapshot(isGeneral: true, accessBehavior: nil))
            #expect(ClipboardWriter.shouldSnapshot(isGeneral: false, accessBehavior: nil))
        }
    }

    @Test func disallowedSnapshotNeverReadsAndStillAttemptsTheWrite() {
        withPasteboard { board in
            for succeeds in [false, true] {
                #expect(board.setString("Previous private text", forType: .string))
                var reads = 0
                var writes = 0
                let result = ClipboardWriter.replaceContents(of: board, snapshotPermitted: false, takeSnapshot: {
                    reads += 1
                    return nil
                }, using: {
                    writes += 1
                    return succeeds ? board.setString("New text", forType: .string) : false
                })
                #expect(result == succeeds)
                #expect(reads == 0)
                #expect(writes == 1)
                #expect(board.string(forType: .string) == (succeeds ? "New text" : nil))
            }
        }
    }
}
