import Foundation

/// Puts an item back from the Trash to the place it was moved from.
public struct Restorer: Sendable {
    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case notMoved
        case missingInTrash
        case originalExists
        case parentMissing
        case failed(String)

        public var description: String {
            switch self {
            case .notMoved: "The item did not go to the Trash."
            case .missingInTrash: "The item is no longer in the Trash."
            case .originalExists: "Something is at the original place now. Restore it in Finder."
            case .parentMissing: "The original folder is gone. Restore it in Finder."
            case .failed(let error): error
            }
        }
    }

    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    /// Moves the Trash item of `entry` back and records the restore. It
    /// never replaces anything at the original place.
    public func restore(_ entry: JournalEntry, journal: (any Journal)?) throws(Refusal) {
        guard entry.outcome == .moved, let detail = entry.detail else { throw .notMoved }
        let source = URL(filePath: detail)
        let target = URL(filePath: entry.path)
        guard FileStatus(lstatPath: source.fileSystemPath) != nil else { throw .missingInTrash }
        guard FileStatus(lstatPath: target.fileSystemPath) == nil else { throw .originalExists }
        guard FileStatus(lstatPath: target.deletingLastPathComponent().fileSystemPath)?.isDirectory == true else {
            throw .parentMissing
        }
        do {
            try FileManager.default.moveItem(at: source, to: target)
        } catch {
            throw .failed(error.localizedDescription)
        }
        try? journal?.record(JournalEntry(
            timestamp: now(), action: entry.action, outcome: .restored, ruleID: entry.ruleID,
            bytes: entry.bytes, path: entry.path, detail: detail
        ))
    }
}
