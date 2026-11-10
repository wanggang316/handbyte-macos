import Foundation
import Testing
@testable import HandbyteCore

/// Records journal entries in memory.
private final class MemoryJournal: Journal, @unchecked Sendable {
    var entries: [JournalEntry] = []
    func record(_ entry: JournalEntry) throws { entries.append(entry) }
}

@Suite("Collector")
struct CollectorTests {
    /// A fake Trash: a rename into a folder of the test home.
    private func fakeTrash(_ home: TemporaryHome) throws -> @Sendable (URL) throws -> URL {
        let trash = try home.makeDirectory(".Trash")
        return { url in
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    @Test func movesFilesAndFoldersToTheTrashAndRecordsThem() async throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        let file = try home.writeFile("Downloads/old.dmg", size: 5000)
        try home.writeFile("Documents/archive/a.txt", size: 100)
        let folder = home.path("Documents/archive")
        let policy = CollectPolicy(home: home.url, exclusions: [])
        let items = try [file, folder].map { try #require(policy.item(at: $0, size: 7)) }
        let journal = MemoryJournal()

        let outcomes = Collector(trash: try fakeTrash(home)).collect(items, policy: policy, journal: journal)

        #expect(outcomes.map(\.status).allSatisfy { if case .moved = $0 { true } else { false } })
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(journal.entries.map(\.ruleID) == ["collected", "collected"])
        #expect(journal.entries.map(\.outcome) == [.moved, .moved])
        #expect(journal.entries.map(\.bytes) == [7, 7])
    }

    @Test func refusesStructuralPrivateOutsideExcludedAndLinkedPaths() throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        for relative in ["Documents/x", "Library/x", "Library/Keychains/k/x", "Library/Mobile Documents/d/x", ".Trash/old/x", "Downloads/keep"] {
            try home.writeFile(relative, size: 1)
        }
        let policy = CollectPolicy(home: home.url, exclusions: [home.path("Downloads/keep").standardizedFileSystemPath])
        for relative in ["", "Documents", "Library", "Library/Keychains/k", "Library/Mobile Documents/d", ".Trash/old", "Downloads/keep"] {
            #expect(policy.reason(for: relative.isEmpty ? home.url : home.path(relative)) != nil, "\(relative)")
        }
        #expect(policy.reason(for: URL(filePath: "/private/etc/hosts")) != nil)
        try home.symlink("Downloads/link", to: "Documents")
        #expect(policy.reason(for: home.path("Downloads/link")) != nil)
        #expect(policy.reason(for: home.path("Downloads/link/x")) != nil)
        #expect(policy.reason(for: home.path("Documents/x")) == nil)
    }

    @Test func skipsAChangedItemAndAChildOfASelectedFolder() throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        let child = try home.writeFile("Documents/project/big.bin", size: 100)
        let other = try home.writeFile("Downloads/replaced.bin", size: 100)
        let policy = CollectPolicy(home: home.url, exclusions: [])
        let items = try [home.path("Documents/project"), child, other].map { try #require(policy.item(at: $0, size: 1)) }
        try FileManager.default.removeItem(at: other)
        try home.writeFile("Downloads/replaced.bin", size: 100)

        let outcomes = Collector(trash: try fakeTrash(home)).collect(items, policy: policy, journal: nil)

        #expect(outcomes.count == 3)
        if case .moved = outcomes[0].status {} else { Issue.record("the folder must move: \(outcomes[0].status)") }
        if case .skipped = outcomes[1].status {} else { Issue.record("the child must be skipped: \(outcomes[1].status)") }
        if case .skipped = outcomes[2].status {} else { Issue.record("the changed file must be skipped: \(outcomes[2].status)") }
        #expect(FileManager.default.fileExists(atPath: other.path))
    }
}
