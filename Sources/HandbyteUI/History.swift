import Foundation
import HandbyteCore

/// The History section: the journal, newest first, with the moves that can
/// still be put back. The journal is shared with the CLI, so its actions are
/// listed too.
public struct HistoryList: Sendable, Equatable {
    public struct Item: Sendable, Equatable, Identifiable {
        public let entry: JournalEntry
        /// A move to the Trash that was not put back yet.
        public let canRestore: Bool
        public let restored: Bool
        /// Items that one restore puts back: the movable members of the
        /// group, or 1.
        public let restoreCount: Int
        public var id: String { entry.id }
    }

    public let items: [Item]

    public init(entries: [JournalEntry]) {
        var groupSizes: [String: Int] = [:]
        for entry in entries where entry.canRestore {
            if let group = entry.group { groupSizes[group, default: 0] += 1 }
        }
        // Newest first; of two entries with one time, the later line first.
        let ordered = entries.enumerated().sorted { a, b in
            a.element.timestamp != b.element.timestamp ? a.element.timestamp > b.element.timestamp : a.offset > b.offset
        }.map(\.element)
        items = ordered.map { entry in
            Item(
                entry: entry,
                canRestore: entry.canRestore,
                restored: entry.outcome == .restored,
                restoreCount: entry.group.flatMap { groupSizes[$0] } ?? 1
            )
        }
    }

    /// Bytes removed and moved, for the header. A restored item is not
    /// counted as moved.
    public var removedBytes: Int64 { items.filter { $0.entry.outcome == .removed }.reduce(0) { $0 + $1.entry.bytes } }
    public var movedBytes: Int64 { items.filter { $0.entry.outcome == .moved }.reduce(0) { $0 + $1.entry.bytes } }
}
