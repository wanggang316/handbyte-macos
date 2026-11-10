import Foundation
import HandbyteCore

/// The History section: the journal, newest first, with the moves that can
/// still be put back.
public struct HistoryList: Sendable, Equatable {
    public struct Item: Sendable, Equatable, Identifiable {
        public let entry: JournalEntry
        /// A move to the Trash that was not put back yet.
        public let canRestore: Bool
        public let restored: Bool
        public var id: String { "\(entry.timestamp.timeIntervalSince1970)|\(entry.path)|\(entry.outcome.rawValue)" }
    }

    public let items: [Item]

    public init(entries: [JournalEntry]) {
        // A restore line names the move it undid by the path and the Trash place.
        let restored = Set(entries.filter { $0.outcome == .restored }.map { "\($0.path)|\($0.detail ?? "")" })
        items = entries
            .filter { $0.outcome != .restored }
            .reversed()
            .map { entry in
                let undone = restored.contains("\(entry.path)|\(entry.detail ?? "")")
                return Item(entry: entry, canRestore: entry.outcome == .moved && !undone, restored: entry.outcome == .moved && undone)
            }
    }

    /// Bytes removed and moved, for the header.
    public var removedBytes: Int64 { items.filter { $0.entry.outcome == .removed }.reduce(0) { $0 + $1.entry.bytes } }
    public var movedBytes: Int64 { items.filter { $0.entry.outcome == .moved }.reduce(0) { $0 + $1.entry.bytes } }
}
