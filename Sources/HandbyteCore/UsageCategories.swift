import Foundation

/// The categories of the storage views, read from the shared catalog
/// (`Resources/catalog/storage.json`). A category owns the trees below its
/// paths; the longest path wins.
public struct StorageCatalog: Sendable {
    public struct Category: Sendable, Hashable, Decodable, Identifiable {
        public let id: String
        public let title: String
        public let paths: [String]
        /// The configured project roots belong to this category too.
        public let projectRoots: Bool?
    }

    /// One path rule with the home folder expanded.
    public struct CategoryPath: Sendable, Hashable {
        public let path: String
        public let category: String
    }

    /// The category of what no path rule covers.
    public static let other = "other"

    public let categories: [Category]

    public static let shared: StorageCatalog = {
        guard let url = Bundle.module.url(forResource: "storage", withExtension: "json", subdirectory: "catalog") else {
            fatalError("catalog: storage.json is not in the resource bundle")
        }
        do {
            return try StorageCatalog(data: Data(contentsOf: url))
        } catch {
            // A defective catalog is a build defect, not a runtime condition.
            fatalError("catalog: \(error)")
        }
    }()

    struct Defect: Error, CustomStringConvertible {
        let description: String
    }

    init(data: Data) throws {
        struct File: Decodable {
            let version: Int
            let categories: [Category]
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.version == 1 else { throw Defect(description: "unsupported version \(file.version)") }
        guard file.categories.contains(where: { $0.id == Self.other }) else {
            throw Defect(description: "the category other is required")
        }
        categories = file.categories
    }

    public func title(of id: String) -> String {
        categories.first { $0.id == id }?.title ?? id
    }

    public func paths(home: URL, projectRoots: [String]) -> [CategoryPath] {
        func expand(_ template: String) -> String {
            let path = PathTemplate.expand(template, home: home).path(percentEncoded: false)
            return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        return categories.flatMap { category in
            let roots = category.projectRoots == true ? projectRoots : []
            return (category.paths + roots).map { CategoryPath(path: expand($0), category: category.id) }
        }
    }
}

/// The content of one storage category.
public struct CategoryTotal: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public var allocatedBytes: Int64
    public var logicalBytes: Int64

    public init(id: String, allocatedBytes: Int64, logicalBytes: Int64) {
        self.id = id
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
    }
}

/// Sums a scan result by the path rules of the storage catalog, by the
/// same rule as `usage.Categorize` of the Go CLI.
public enum UsageCategories {
    public static func totals(of result: UsageResult, paths: [StorageCatalog.CategoryPath]) -> [CategoryTotal] {
        var totals: [String: CategoryTotal] = [:]
        func add(_ id: String, _ allocated: Int64, _ logical: Int64) {
            guard allocated != 0 || logical != 0 else { return }
            totals[id, default: CategoryTotal(id: id, allocatedBytes: 0, logicalBytes: 0)].allocatedBytes += allocated
            totals[id]?.logicalBytes += logical
        }
        func category(of path: String) -> String {
            var best = -1
            var id = StorageCatalog.other
            for rule in paths where (path == rule.path || isBelow(path, rule.path)) && rule.path.utf8.count > best {
                best = rule.path.utf8.count
                id = rule.category
            }
            return id
        }
        func walk(_ node: UsageNode, _ path: String) {
            let id = category(of: path)
            guard node.isDirectory, paths.contains(where: { isBelow($0.path, path) }) else {
                add(id, node.allocatedBytes, node.logicalBytes)
                return
            }
            var allocated = node.otherAllocatedBytes
            var logical = node.logicalBytes
            for child in node.children {
                logical -= child.logicalBytes
                if child.isDirectory {
                    walk(child, path == "/" ? "/" + child.name : path + "/" + child.name)
                } else {
                    allocated += child.allocatedBytes
                    logical += child.logicalBytes
                }
            }
            add(id, allocated, logical)
        }
        walk(result.root, result.path)
        return totals.values.sorted {
            $0.allocatedBytes != $1.allocatedBytes ? $0.allocatedBytes > $1.allocatedBytes : $0.id < $1.id
        }
    }

    /// Whether `path` is strictly inside `directory`.
    public static func isBelow(_ path: String, _ directory: String) -> Bool {
        if directory == "/" { return path != "/" && path.hasPrefix("/") }
        return path.count > directory.count && path.hasPrefix(directory + "/")
    }
}

/// The short form of a scan that is kept between runs, so that a screen can
/// show the last result at once and replace it when a new scan is ready.
public struct UsageSummary: Sendable, Hashable, Codable {
    public struct Entry: Sendable, Hashable, Codable {
        public let name: String
        public let isDirectory: Bool
        public let allocatedBytes: Int64
    }

    public var path: String
    public var scannedAt: Date
    public var allocatedBytes: Int64
    public var logicalBytes: Int64
    public var fileCount: Int
    public var incomplete: Bool
    public var categories: [CategoryTotal]
    /// One entry for each direct child of the scanned folder.
    public var top: [Entry]

    public init(
        path: String, scannedAt: Date, allocatedBytes: Int64 = 0, logicalBytes: Int64 = 0, fileCount: Int = 0,
        incomplete: Bool = false, categories: [CategoryTotal] = [], top: [Entry] = []
    ) {
        self.path = path
        self.scannedAt = scannedAt
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.fileCount = fileCount
        self.incomplete = incomplete
        self.categories = categories
        self.top = top
    }

    public init(result: UsageResult, categories: [CategoryTotal], at date: Date) {
        self.init(
            path: result.path, scannedAt: date, allocatedBytes: result.root.allocatedBytes,
            logicalBytes: result.root.logicalBytes, fileCount: result.root.fileCount, incomplete: result.root.incomplete,
            categories: categories,
            top: result.root.children.map { Entry(name: $0.name, isDirectory: $0.isDirectory, allocatedBytes: $0.allocatedBytes) }
        )
    }
}

/// Keeps the newest summaries of a few folders in one file.
public struct UsageSummaryStore: Sendable {
    public static let limit = 8
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultURL(home: URL) -> URL {
        home.appending(path: "Library/Application Support/Handbyte/usage.json", directoryHint: .notDirectory)
    }

    private struct File: Codable {
        var version = 1
        var summaries: [UsageSummary]
    }

    private static let coder: (JSONEncoder, JSONDecoder) = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (encoder, decoder)
    }()

    public func load(path: String) -> UsageSummary? {
        read().first { $0.path == path }
    }

    /// A cancelled scan must not be stored: its numbers are too low.
    public func save(_ summary: UsageSummary) throws {
        var kept = [summary] + read().filter { $0.path != summary.path }
        kept.sort { $0.scannedAt > $1.scannedAt }
        let data = try Self.coder.0.encode(File(summaries: Array(kept.prefix(Self.limit))))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private func read() -> [UsageSummary] {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? Self.coder.1.decode(File.self, from: data),
              file.version == 1
        else { return [] }
        return file.summaries
    }
}
