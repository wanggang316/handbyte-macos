import Foundation
import Testing
import HandbyteCore
@testable import HandbyteUI

@Suite("History")
struct HistoryTests {
    @Test func newestFirstAndARestoredMoveCannotBeRestoredAgain() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let entries = [
            JournalEntry(timestamp: t0, action: .removePermanently, outcome: .removed, ruleID: "go-build", bytes: 100, path: "/a", detail: nil),
            JournalEntry(timestamp: t0.addingTimeInterval(1), action: .trash, outcome: .moved, ruleID: "collected", bytes: 10, path: "/b", detail: "/T/b"),
            JournalEntry(timestamp: t0.addingTimeInterval(2), action: .trash, outcome: .moved, ruleID: "collected", bytes: 20, path: "/c", detail: "/T/c"),
            JournalEntry(timestamp: t0.addingTimeInterval(3), action: .trash, outcome: .restored, ruleID: "collected", bytes: 10, path: "/b", detail: "/T/b"),
        ]
        let list = HistoryList(entries: entries)
        #expect(list.items.map(\.entry.path) == ["/c", "/b", "/a"])
        #expect(list.items.map(\.canRestore) == [true, false, false])
        #expect(list.items.map(\.restored) == [false, true, false])
        #expect(list.removedBytes == 100)
        #expect(list.movedBytes == 30)
    }
}
