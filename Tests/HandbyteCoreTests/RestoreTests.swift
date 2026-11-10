import Foundation
import Testing
@testable import HandbyteCore

@Suite("Restore")
struct RestoreTests {
    @Test func journalLinesReadBackWithEscapes() throws {
        let entry = JournalEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000), action: .trash, outcome: .moved, ruleID: "collected",
            bytes: 42, path: "/Users/a/x\ty\\z", detail: "/Users/a/.Trash/x\ny"
        )
        #expect(JournalEntry(line: entry.line) == entry)
        #expect(JournalEntry(line: "not a journal line") == nil)
    }

    @Test func putsAnItemBackAndRecordsIt() throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        let original = try home.writeFile("Downloads/old.dmg", size: 10)
        let trash = try home.makeDirectory(".Trash")
        let moved = trash.appending(path: "old.dmg")
        try FileManager.default.moveItem(at: original, to: moved)
        let journal = OperationsJournal(fileURL: home.url.appending(path: "ops.log"))
        let entry = JournalEntry(timestamp: .now, action: .trash, outcome: .moved, ruleID: "collected", bytes: 10, path: original.fileSystemPath, detail: moved.fileSystemPath)
        try journal.record(entry)

        try Restorer().restore(entry, journal: journal)

        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(!FileManager.default.fileExists(atPath: moved.path))
        #expect(try journal.entries().map(\.outcome) == [.moved, .restored])
    }

    @Test func refusesToReplaceOrToRestoreWhatIsGone() throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        let original = try home.writeFile("Downloads/a.bin", size: 10)
        let inTrash = try home.writeFile(".Trash/a.bin", size: 10)
        let entry = JournalEntry(timestamp: .now, action: .trash, outcome: .moved, ruleID: "x", bytes: 10, path: original.fileSystemPath, detail: inTrash.fileSystemPath)

        #expect(throws: Restorer.Refusal.originalExists) { try Restorer().restore(entry, journal: nil) }
        try FileManager.default.removeItem(at: original)
        try FileManager.default.removeItem(at: inTrash)
        #expect(throws: Restorer.Refusal.missingInTrash) { try Restorer().restore(entry, journal: nil) }
        let removed = JournalEntry(timestamp: .now, action: .removePermanently, outcome: .removed, ruleID: "x", bytes: 10, path: original.fileSystemPath, detail: nil)
        #expect(throws: Restorer.Refusal.notMoved) { try Restorer().restore(removed, journal: nil) }
    }
}
