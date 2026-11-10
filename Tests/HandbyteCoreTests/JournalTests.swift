import Foundation
import Testing
@testable import HandbyteCore

/// One case of `Conformance/journal`, shared with the Go CLI.
private struct JournalCase: Decodable {
    struct Expect: Decodable {
        let id: String
        let outcome: String
        let canRestore: Bool
        let group: String
        let bytes: Int64
    }

    let name: String
    let lines: [String]
    let expect: [Expect]
}

@Suite("OperationsJournal")
struct OperationsJournalTests {
    @Test func theJournalIsTheFileOfTheCLI() {
        let home = URL(filePath: "/Volumes/Test/alice", directoryHint: .isDirectory)
        #expect(OperationsJournal.defaultURL(home: home).path == "/Volumes/Test/alice/Library/Application Support/handbyte/actions.jsonl")
        #expect(OperationsJournal.legacyURL(home: home).path == "/Volumes/Test/alice/Library/Logs/handbyte/operations.log")
    }

    @Test func readsTheSharedConformanceCase() throws {
        let directory = try #require(Bundle.module.url(forResource: "Conformance", withExtension: nil))
        let data = try Data(contentsOf: directory.appending(path: "journal/history.json"))
        let journalCase = try JSONDecoder().decode(JournalCase.self, from: data)
        let fixture = try CleaningFixture()
        let journal = OperationsJournal(fileURL: fixture.root.appending(path: "actions.jsonl"))
        try Data((journalCase.lines.joined(separator: "\n") + "\n").utf8).write(to: journal.fileURL)

        let entries = try journal.entries()

        let expected = journalCase.expect.filter { $0.outcome != "none" }
        #expect(entries.map(\.id) == expected.map(\.id), "\(journalCase.name)")
        for (entry, want) in zip(entries, expected) {
            #expect(entry.outcome.rawValue == want.outcome, "\(want.id)")
            #expect(entry.canRestore == want.canRestore, "\(want.id)")
            #expect((entry.group ?? "") == want.group, "\(want.id)")
            #expect(entry.bytes == want.bytes, "\(want.id)")
        }
        // Go writes nanoseconds and a zone offset.
        let first = try #require(entries.first)
        #expect(abs(first.timestamp.timeIntervalSince1970 - 1_794_298_501.5) < 0.001)
    }

    @Test func writesALineThatReadsBackWithTheSameState() throws {
        let fixture = try CleaningFixture()
        let journal = OperationsJournal(fileURL: fixture.root.appending(path: "a/actions.jsonl"))
        let stamp = Date(timeIntervalSince1970: 1_700_000_000.25)
        let moved = JournalEntry(
            id: "m", timestamp: stamp, action: .trash, outcome: .moved, ruleID: "xcode-derived", bytes: 4096,
            path: "/Users/alice/Library/Developer/Xcode/DerivedData", detail: "/Users/alice/.Trash/DerivedData",
            group: "app-1", trashIdentity: FileIdentity(dev: 16_777_232, ino: 9))
        try journal.record(moved)
        try journal.record(JournalEntry(
            id: "f", timestamp: stamp, action: .removePermanently, outcome: .failed, ruleID: "npm-cache", bytes: 0,
            path: "/Users/alice/.npm/_cacache", detail: "Operation not permitted"))

        let text = try String(contentsOf: journal.fileURL, encoding: .utf8)
        #expect(text.split(separator: "\n").count == 2)
        #expect(text.hasSuffix("\n"))
        #expect(text.contains(#""Status":"trashed""#))
        #expect(text.contains(#""Tool":"app""#))
        #expect(text.contains(#""TrashIdentity":{"#))
        let entries = try journal.entries()
        #expect(entries.first == moved)
        #expect(entries.last?.detail == "Operation not permitted")
    }

    @Test func refusesToWriteAfterAnIncompleteLine() throws {
        let fixture = try CleaningFixture()
        let journal = OperationsJournal(fileURL: fixture.root.appending(path: "actions.jsonl"))
        try Data(#"{"ID":"x""#.utf8).write(to: journal.fileURL)
        let entry = JournalEntry(timestamp: .now, action: .trash, outcome: .removed, ruleID: "r", bytes: 1, path: "/x", detail: nil)
        #expect(throws: OperationsJournal.Failure.unterminatedRecord) { try journal.record(entry) }
    }

    @Test func readsTheLegacyLogForHistory() throws {
        let fixture = try CleaningFixture()
        let legacy = fixture.root.appending(path: "operations.log")
        try Data("2023-11-14T22:13:20Z\ttrash\tmoved\tcollected\t7\t/tmp/a\\tb\t/T/a\n".utf8).write(to: legacy)
        let journal = OperationsJournal(fileURL: fixture.root.appending(path: "actions.jsonl"), legacyURL: legacy)

        let entries = try journal.entries()

        #expect(entries.map(\.path) == ["/tmp/a\tb"])
        #expect(entries.map(\.canRestore) == [false])
    }
}
