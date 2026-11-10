import Foundation
import HandbyteCore

/// The position in a scanned tree and the rows of the opened folder. The
/// storage view is read-only: it shows sizes and opens folders.
public struct StorageBrowser: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        /// Nil for the row that sums the small files.
        public let path: String?
        public let isDirectory: Bool
        public let allocatedBytes: Int64
        public let logicalBytes: Int64
        public let fileCount: Int
        /// Part of the opened folder, between 0 and 1.
        public let share: Double
        public let canOpen: Bool
        /// Why the folder was not measured.
        public let note: String?
        /// The size is a lower bound.
        public let incomplete: Bool
    }

    public struct Crumb: Sendable, Equatable, Identifiable {
        public let title: String
        /// 0 is the root of the scan.
        public let depth: Int
        public var id: Int { depth }
    }

    public let rootPath: String
    public let root: UsageNode
    /// Names of the opened folders below the root.
    public private(set) var trail: [String] = []

    public init(rootPath: String, root: UsageNode) {
        self.rootPath = rootPath
        self.root = root
    }

    /// The opened folder.
    public var current: UsageNode {
        var node = root
        for name in trail {
            guard let next = node.children.first(where: { $0.isDirectory && $0.name == name }) else { break }
            node = next
        }
        return node
    }

    public var currentPath: String {
        trail.reduce(rootPath) { Self.join($0, $1) }
    }

    public var crumbs: [Crumb] {
        let rootTitle = rootPath == "/" ? "/" : URL(filePath: rootPath).lastPathComponent
        return [Crumb(title: rootTitle, depth: 0)] + trail.enumerated().map { Crumb(title: $1, depth: $0 + 1) }
    }

    public var rows: [Row] {
        let folder = current
        let base = currentPath
        let total = Double(folder.allocatedBytes)
        func share(_ bytes: Int64) -> Double { total > 0 ? Double(bytes) / total : 0 }
        var rows = folder.children.map { child in
            Row(
                id: child.name,
                title: child.name,
                path: Self.join(base, child.name),
                isDirectory: child.isDirectory,
                allocatedBytes: child.allocatedBytes,
                logicalBytes: child.logicalBytes,
                fileCount: child.fileCount,
                share: share(child.allocatedBytes),
                canOpen: child.isDirectory && child.skipped == nil,
                note: child.skipped,
                incomplete: child.incomplete
            )
        }
        if folder.otherFileCount > 0 {
            rows.append(Row(
                // A file name cannot contain a slash, so this cannot collide.
                id: "/other",
                title: "\(folder.otherFileCount) smaller files",
                path: nil,
                isDirectory: false,
                allocatedBytes: folder.otherAllocatedBytes,
                logicalBytes: 0,
                fileCount: folder.otherFileCount,
                share: share(folder.otherAllocatedBytes),
                canOpen: false,
                note: nil,
                incomplete: false
            ))
        }
        return rows
    }

    public mutating func open(_ row: Row) {
        guard row.canOpen else { return }
        trail.append(row.title)
    }

    /// Goes up to the folder at `depth` of the crumbs.
    public mutating func leave(to depth: Int) {
        trail = Array(trail.prefix(max(0, depth)))
    }

    private static func join(_ base: String, _ name: String) -> String {
        base == "/" ? "/" + name : base + "/" + name
    }
}
