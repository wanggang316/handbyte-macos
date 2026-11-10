import Foundation

/// A file or a folder that the user picked in the storage view. No cleanup
/// rule covers it, so it only ever goes to the Trash.
public struct CollectedItem: Sendable, Hashable, Identifiable {
    public let url: URL
    public let identity: FileIdentity
    public let isDirectory: Bool
    /// Bytes measured by the storage scan.
    public let size: Int64
    public var id: String { url.fileSystemPath }
}

/// Which paths may be collected. The same lists as the collector of the Go
/// CLI (`internal/cleaner/collect.go`).
public struct CollectPolicy: Sendable {
    /// Never collected, as a whole or below: accounts, keys, mail and files
    /// that sync elsewhere.
    static let privateFolders = [
        ".Trash",
        "Library/Accounts",
        "Library/CloudStorage",
        "Library/Cookies",
        "Library/Keychains",
        "Library/Mail",
        "Library/Messages",
        "Library/Mobile Documents",
        "Library/Preferences",
        "Library/Safari",
    ]

    /// May hold collected items but are not collected as a whole.
    static let structuralFolders = [
        "Applications", "Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public",
        "Library/Application Support", "Library/Caches", "Library/Containers", "Library/Group Containers", "Library/Logs",
    ]

    let home: String
    let exclusions: Set<String>

    /// `exclusions` are the absolute paths of the settings.
    public init(home: URL, exclusions: [String]) {
        self.home = UsageScanner.physicalPath(home) ?? home.fileSystemPath
        // An entry is compared as the kernel sees it: URL standardization can
        // drop the /private prefix of a path.
        self.exclusions = Set(exclusions.flatMap { entry in
            [entry, UsageScanner.physicalPath(URL(filePath: entry))].compactMap { $0 }
        })
    }

    /// Why `url` cannot be collected, or nil.
    public func reason(for url: URL) -> String? {
        let path = url.fileSystemPath
        guard path.hasPrefix("/"), path != home, UsageCategories.isBelow(path, home) else {
            return "Only items inside the home folder can be collected."
        }
        guard UsageScanner.physicalPath(url) == path, FileStatus(lstatPath: path)?.isSymbolicLink == false else {
            return "The path goes through a symbolic link."
        }
        for folder in Self.privateFolders {
            let protected = home + "/" + folder
            if path == protected || UsageCategories.isBelow(path, protected) {
                return "~/\(folder) holds private data and is never collected."
            }
        }
        if let folder = Self.structuralFolders.first(where: { path == home + "/" + $0 }) {
            return "~/\(folder) is a standard folder. Collect the items in it."
        }
        if exclusions.contains(where: { path == $0 || UsageCategories.isBelow(path, $0) || UsageCategories.isBelow($0, path) }) {
            return "Protected by an exclusion."
        }
        return nil
    }

    /// Checks `url` and binds it to its file system object.
    public func item(at url: URL, size: Int64) -> CollectedItem? {
        guard reason(for: url) == nil, let status = FileStatus(lstatPath: url.fileSystemPath) else { return nil }
        return CollectedItem(url: url, identity: status.identity, isDirectory: status.isDirectory, size: size)
    }
}

/// Moves collected items to the Trash, one at a time, and records each move.
/// An item inside another selected folder goes with that folder.
public struct Collector: Sendable {
    public struct Outcome: Sendable, Hashable {
        public enum Status: Sendable, Hashable {
            case moved(URL)
            case skipped(reason: String)
            case failed(error: String)
        }

        public let item: CollectedItem
        public let status: Status
    }

    private let trash: @Sendable (URL) throws -> URL
    private let now: @Sendable () -> Date

    /// `trash` moves a URL to the Trash and returns the destination. Tests
    /// replace it; the default is the system file manager.
    public init(
        trash: @escaping @Sendable (URL) throws -> URL = Collector.systemTrash,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.trash = trash
        self.now = now
    }

    public static let systemTrash: @Sendable (URL) throws -> URL = { url in
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        return (destination as URL?) ?? url
    }

    public func collect(_ items: [CollectedItem], policy: CollectPolicy, journal: (any Journal)?) -> [Outcome] {
        items.map { item in
            if items.contains(where: { $0.url != item.url && UsageCategories.isBelow(item.url.fileSystemPath, $0.url.fileSystemPath) }) {
                return Outcome(item: item, status: .skipped(reason: "Goes with the selected folder that holds it."))
            }
            // Check again at the action boundary.
            if let reason = policy.reason(for: item.url) {
                return Outcome(item: item, status: .skipped(reason: reason))
            }
            guard FileStatus(lstatPath: item.url.fileSystemPath)?.identity == item.identity else {
                return Outcome(item: item, status: .skipped(reason: "The item changed since review. Scan again."))
            }
            let status: Outcome.Status
            do {
                status = .moved(try trash(item.url))
            } catch {
                status = .failed(error: error.localizedDescription)
            }
            let entry: JournalEntry = switch status {
            case .moved(let destination):
                JournalEntry(timestamp: now(), action: .trash, outcome: .moved, ruleID: "collected", bytes: item.size, path: item.url.fileSystemPath, detail: destination.fileSystemPath)
            case .failed(let error), .skipped(let error):
                JournalEntry(timestamp: now(), action: .trash, outcome: .failed, ruleID: "collected", bytes: 0, path: item.url.fileSystemPath, detail: error)
            }
            // The move already happened; a journal write failure must not
            // turn it into a reported failure.
            try? journal?.record(entry)
            return Outcome(item: item, status: status)
        }
    }
}
