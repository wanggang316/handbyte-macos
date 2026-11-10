import Foundation

/// Puts an item back from the Trash to the place it was moved from.
public struct Restorer: Sendable {
    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case notMoved
        case missingInTrash
        case changedInTrash
        case originalExists
        case parentMissing
        case failed(String)

        public var description: String {
            switch self {
            case .notMoved: "The item did not go to the Trash, or its place in the Trash is not known."
            case .missingInTrash: "The item is no longer in the Trash."
            case .changedInTrash: "The item in the Trash changed. Restore it in Finder."
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

    /// Moves the Trash item of `entry` back and records the restore as the
    /// new state of the same action. It never replaces anything at the
    /// original place, and it checks that the Trash item is the one that
    /// was moved.
    public func restore(_ entry: JournalEntry, journal: (any Journal)?) throws(Refusal) {
        guard entry.canRestore, let detail = entry.detail, let identity = entry.trashIdentity else { throw .notMoved }
        let source = URL(filePath: detail)
        let target = URL(filePath: entry.path)
        guard let status = FileStatus(lstatPath: source.fileSystemPath) else { throw .missingInTrash }
        // The CLI can write a device that Go widened with its sign; compare
        // the 32 bits of st_dev.
        guard status.identity.ino == identity.ino,
              UInt32(truncatingIfNeeded: status.identity.dev) == UInt32(truncatingIfNeeded: identity.dev),
              !status.isSymbolicLink
        else { throw .changedInTrash }
        guard FileStatus(lstatPath: target.fileSystemPath) == nil else { throw .originalExists }
        guard FileStatus(lstatPath: target.deletingLastPathComponent().fileSystemPath)?.isDirectory == true else {
            throw .parentMissing
        }
        do {
            try FileManager.default.moveItem(at: source, to: target)
        } catch {
            throw .failed(error.localizedDescription)
        }
        var restored = entry
        restored.timestamp = now()
        restored.outcome = .restored
        try? journal?.record(restored)
    }

    /// Restores every entry that `canRestore` in the group of `entry`, or
    /// `entry` alone when it has no group. Returns the refusals by path.
    public func restoreGroup(of entry: JournalEntry, in entries: [JournalEntry], journal: (any Journal)?) -> [(path: String, refusal: Refusal)] {
        let members = entry.group.map { group in entries.filter { $0.group == group && $0.canRestore } } ?? [entry]
        var refusals: [(path: String, refusal: Refusal)] = []
        for member in members {
            do throws(Refusal) {
                try restore(member, journal: journal)
            } catch {
                refusals.append((member.path, error))
            }
        }
        return refusals
    }
}
