import Foundation
import Testing
import HandbyteCore
@testable import HandbyteUI

@Suite("History")
struct HistoryTests {
    @Test func newestFirstAndARestoredMoveCannotBeRestoredAgain() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let identity = FileIdentity(dev: 1, ino: 2)
        let entries = [
            JournalEntry(id: "a", timestamp: t0, action: .removePermanently, outcome: .removed, ruleID: "go-build", bytes: 100, path: "/a", detail: nil),
            JournalEntry(id: "b", timestamp: t0.addingTimeInterval(3), action: .trash, outcome: .restored, ruleID: "collected", bytes: 10, path: "/b", detail: "/T/b", trashIdentity: identity),
            JournalEntry(id: "c", timestamp: t0.addingTimeInterval(2), action: .trash, outcome: .moved, ruleID: "collected", bytes: 20, path: "/c", detail: "/T/c", trashIdentity: identity),
        ]
        let list = HistoryList(entries: entries)
        #expect(list.items.map(\.entry.path) == ["/b", "/c", "/a"])
        #expect(list.items.map(\.canRestore) == [false, true, false])
        #expect(list.items.map(\.restored) == [true, false, false])
        #expect(list.removedBytes == 100)
        #expect(list.movedBytes == 20)
    }

    @Test func oneRestorePutsBackTheMovableMembersOfAGroup() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let identity = FileIdentity(dev: 1, ino: 2)
        func moved(_ id: String, group: String?, identity: FileIdentity?) -> JournalEntry {
            JournalEntry(id: id, timestamp: t0, action: .trash, outcome: .moved, ruleID: "app:x", bytes: 1, path: "/\(id)", detail: "/T/\(id)", group: group, trashIdentity: identity)
        }
        let list = HistoryList(entries: [
            moved("app", group: "g", identity: identity),
            moved("cache", group: "g", identity: identity),
            moved("lost", group: "g", identity: nil),
            moved("alone", group: nil, identity: identity),
        ])
        #expect(list.items.map(\.entry.id) == ["alone", "lost", "cache", "app"])
        #expect(list.items.map(\.restoreCount) == [1, 2, 2, 2])
        #expect(list.items.map(\.canRestore) == [true, false, true, true])
    }
}
