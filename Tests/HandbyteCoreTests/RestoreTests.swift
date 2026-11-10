import Foundation
import Testing
@testable import HandbyteCore

@Suite("Restore")
struct RestoreTests {
    @Test func putsAnItemBackAndRecordsItAsTheNewStateOfTheAction() throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        let original = try home.writeFile("Downloads/old.dmg", size: 10)
        let trash = try home.makeDirectory(".Trash")
        let moved = trash.appending(path: "old.dmg")
        try FileManager.default.moveItem(at: original, to: moved)
        let journal = OperationsJournal(fileURL: home.url.appending(path: "actions.jsonl"))
        try journal.record(JournalEntry(timestamp: .now, action: .trash, outcome: .moved, ruleID: "collected", bytes: 10, path: original.fileSystemPath, detail: moved.fileSystemPath))
        let entry = try #require(try journal.entries().first)
        #expect(entry.canRestore)

        try Restorer().restore(entry, journal: journal)

        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(!FileManager.default.fileExists(atPath: moved.path))
        #expect(try journal.entries().map(\.outcome) == [.restored])
    }

    @Test func refusesToReplaceToRestoreWhatIsGoneOrWhatChanged() throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        let original = try home.writeFile("Downloads/a.bin", size: 10)
        let inTrash = try home.writeFile(".Trash/a.bin", size: 10)
        let identity = try #require(FileStatus(lstatPath: inTrash.fileSystemPath)?.identity)
        let entry = JournalEntry(timestamp: .now, action: .trash, outcome: .moved, ruleID: "x", bytes: 10, path: original.fileSystemPath, detail: inTrash.fileSystemPath, trashIdentity: identity)

        #expect(throws: Restorer.Refusal.originalExists) { try Restorer().restore(entry, journal: nil) }
        try FileManager.default.removeItem(at: original)
        try FileManager.default.removeItem(at: inTrash)
        _ = try home.writeFile(".Trash/a.bin", size: 10)
        #expect(throws: Restorer.Refusal.changedInTrash) { try Restorer().restore(entry, journal: nil) }
        try FileManager.default.removeItem(at: inTrash)
        #expect(throws: Restorer.Refusal.missingInTrash) { try Restorer().restore(entry, journal: nil) }
        var unknown = entry
        unknown.trashIdentity = nil
        #expect(throws: Restorer.Refusal.notMoved) { try Restorer().restore(unknown, journal: nil) }
    }

    @Test func restoresTheMembersOfAGroupTogether() throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        let journal = OperationsJournal(fileURL: home.url.appending(path: "actions.jsonl"))
        var paths: [URL] = []
        for name in ["Notes.app", "Notes-cache"] {
            let original = try home.writeFile("Apps/\(name)", size: 4)
            let moved = home.url.appending(path: ".Trash/\(name)")
            try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: original, to: moved)
            try journal.record(JournalEntry(timestamp: .now, action: .trash, outcome: .moved, ruleID: "app:x", bytes: 4, path: original.fileSystemPath, detail: moved.fileSystemPath, group: "app-1"))
            paths.append(original)
        }
        let entries = try journal.entries()

        let refusals = Restorer().restoreGroup(of: entries[1], in: entries, journal: journal)

        #expect(refusals.isEmpty)
        #expect(paths.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(try journal.entries().map(\.outcome) == [.restored, .restored])
    }
}
