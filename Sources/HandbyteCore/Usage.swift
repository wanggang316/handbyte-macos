import Darwin
import Foundation
import os

/// A directory or a file of a scanned tree. The sizes and the file count of
/// a directory include all that is below it.
public struct UsageNode: Sendable, Hashable {
    public var name: String
    public var isDirectory: Bool
    /// Space on disk.
    public var allocatedBytes: Int64 = 0
    /// Length of the content.
    public var logicalBytes: Int64 = 0
    public var fileCount = 0
    /// The subdirectories and the largest files, largest first. Smaller
    /// files are in `otherFileCount`.
    public var children: [UsageNode] = []
    public var otherFileCount = 0
    public var otherAllocatedBytes: Int64 = 0
    /// This directory, or one below it, could not be read in full. The
    /// sizes are then a lower bound.
    public var incomplete = false
    /// Why a directory was not entered: another volume, or content that is
    /// not on this Mac.
    public var skipped: String?
    public var error: String?

    public init(name: String, isDirectory: Bool) {
        self.name = name
        self.isDirectory = isDirectory
    }
}

/// One entry of the list of largest files.
public struct UsageFile: Sendable, Hashable {
    public let path: String
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
}

/// A snapshot of a running scan.
public struct UsageProgress: Sendable, Hashable {
    /// The running total of one direct child of the root.
    public struct Top: Sendable, Hashable, Identifiable {
        public let name: String
        public let isDirectory: Bool
        public var allocatedBytes: Int64
        public var done: Bool
        public var id: String { name }
    }

    public var fileCount: Int
    public var allocatedBytes: Int64
    public var currentPath: String
    /// One entry for each direct child of the root, in name order.
    public var top: [Top]

    public init(fileCount: Int = 0, allocatedBytes: Int64 = 0, currentPath: String, top: [Top] = []) {
        self.fileCount = fileCount
        self.allocatedBytes = allocatedBytes
        self.currentPath = currentPath
        self.top = top
    }
}

/// The outcome of a scan. After a cancellation it holds what was measured
/// until then.
public struct UsageResult: Sendable, Hashable {
    public let path: String
    public let root: UsageNode
    public let largest: [UsageFile]
    public let cancelled: Bool
    public let elapsed: TimeInterval
}

/// Measures what a directory tree holds. It is the engine of the storage
/// views: it reads sizes, and it never changes a file. The Go CLI has the
/// same engine in `internal/usage`; the conformance cases keep them equal.
public struct UsageScanner: Sendable {
    public struct Options: Sendable {
        /// Directories read at one time.
        public var workers = min(ProcessInfo.processInfo.activeProcessorCount, 12)
        /// Length of the list of largest files.
        public var largestFiles = 100
        /// Files kept as nodes in each directory.
        public var filesPerDirectory = 50

        public init() {}
    }

    public init() {}

    /// The path with all symbolic links resolved, as the kernel sees it.
    /// `URL.resolvingSymlinksInPath()` is not used: it removes `/private`
    /// from paths such as `/private/tmp`, so they no longer match rules.
    public static func physicalPath(_ url: URL) -> String? {
        guard let resolved = realpath(url.path(percentEncoded: false), nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Scans the tree below `url` in the caller's task. Cancelling that task
    /// stops the scan and returns the partial result. Returns nil when `url`
    /// is not a directory. `progress` gets a snapshot about ten times each
    /// second, and one more at the end.
    public func scan(
        _ url: URL,
        options: Options = Options(),
        progress: (@Sendable (UsageProgress) -> Void)? = nil
    ) async -> UsageResult? {
        let started = Date()
        guard let rootPath = UsageScanner.physicalPath(url) else { return nil }
        var status = stat()
        guard lstat(rootPath, &status) == 0, status.st_mode & S_IFMT == S_IFDIR else { return nil }

        var devices: Set<Int32> = [status.st_dev]
        var skipPath: String?
        if rootPath == "/" {
            // The startup disk is two volumes that firmlinks join. Count the
            // data volume through the firmlinks, and do not enter it twice.
            var data = stat()
            if lstat("/System/Volumes/Data", &data) == 0 { devices.insert(data.st_dev) }
            skipPath = "/System/Volumes"
        }
        let run = UsageRun(options: options, devices: devices, skipPath: skipPath, rootPath: rootPath)

        let reporter = progress.map { report in
            Task.detached {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    report(run.snapshot())
                }
            }
        }
        let node = await run.walkRoot()
        reporter?.cancel()
        _ = await reporter?.value
        progress?(run.snapshot())

        return UsageResult(
            path: rootPath,
            root: node,
            largest: run.largestFiles(),
            cancelled: Task.isCancelled,
            elapsed: Date().timeIntervalSince(started)
        )
    }
}

/// Order of rows: largest first, then by name, so that a result is stable.
func usageOrder(_ lhs: UsageNode, _ rhs: UsageNode) -> Bool {
    if lhs.allocatedBytes != rhs.allocatedBytes { return lhs.allocatedBytes > rhs.allocatedBytes }
    if lhs.logicalBytes != rhs.logicalBytes { return lhs.logicalBytes > rhs.logicalBytes }
    return lhs.name.utf8.lexicographicallyPrecedes(rhs.name.utf8)
}

private struct UsageEntry {
    let name: String
    let status: stat
    var isDirectory: Bool { status.st_mode & S_IFMT == S_IFDIR }
    var isRegular: Bool { status.st_mode & S_IFMT == S_IFREG }
}

/// The shared state of one scan.
private final class UsageRun: Sendable {
    private struct State {
        var fileCount = 0
        var allocatedBytes: Int64 = 0
        var currentPath: String
        var top: [UsageProgress.Top] = []
        var topIndex: [String: Int] = [:]
        var links: Set<FileIdentity> = []
        var largest: [UsageFile] = []
        var freeSlots: Int
    }

    private let options: UsageScanner.Options
    private let devices: Set<Int32>
    private let skipPath: String?
    private let rootPath: String
    private let state: OSAllocatedUnfairLock<State>

    init(options: UsageScanner.Options, devices: Set<Int32>, skipPath: String?, rootPath: String) {
        self.options = options
        self.devices = devices
        self.skipPath = skipPath
        self.rootPath = rootPath
        // The caller's task is the first worker.
        state = OSAllocatedUnfairLock(initialState: State(currentPath: rootPath, freeSlots: max(0, options.workers - 1)))
    }

    func snapshot() -> UsageProgress {
        state.withLock {
            UsageProgress(fileCount: $0.fileCount, allocatedBytes: $0.allocatedBytes, currentPath: $0.currentPath, top: $0.top)
        }
    }

    func largestFiles() -> [UsageFile] {
        state.withLock { $0.largest }.sorted(by: Self.fileOrder)
    }

    private static func fileOrder(_ lhs: UsageFile, _ rhs: UsageFile) -> Bool {
        if lhs.allocatedBytes != rhs.allocatedBytes { return lhs.allocatedBytes > rhs.allocatedBytes }
        if lhs.logicalBytes != rhs.logicalBytes { return lhs.logicalBytes > rhs.logicalBytes }
        return lhs.path.utf8.lexicographicallyPrecedes(rhs.path.utf8)
    }

    func walkRoot() async -> UsageNode {
        let (entries, _) = Self.read(rootPath)
        state.withLock { state in
            state.top = entries.map {
                UsageProgress.Top(name: $0.name, isDirectory: $0.isDirectory, allocatedBytes: 0, done: false)
            }
            state.topIndex = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($1.name, $0) })
        }
        let node = await walk(rootPath, name: rootPath, top: nil)
        state.withLock { state in
            for index in state.top.indices { state.top[index].done = true }
        }
        return node
    }

    /// Lists a directory in byte order of the names. Returns the entries it
    /// could read and the first error.
    private static func read(_ path: String) -> ([UsageEntry], String?) {
        guard let directory = opendir(path) else {
            return ([], String(cString: strerror(errno)))
        }
        defer { closedir(directory) }
        var entries: [UsageEntry] = []
        var failure: String?
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            var status = stat()
            if lstat(path == "/" ? "/" + name : path + "/" + name, &status) != 0 {
                if errno != ENOENT, failure == nil { failure = String(cString: strerror(errno)) }
                continue
            }
            entries.append(UsageEntry(name: name, status: status))
        }
        entries.sort { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
        return (entries, failure)
    }

    /// Fills a node from the directory at `path`. `top` is nil only for the
    /// root, where each child gets its own running total; below the root all
    /// sizes go to the total of the top-level entry.
    private func walk(_ path: String, name: String, top: Int?) async -> UsageNode {
        var node = UsageNode(name: name, isDirectory: true)
        if Task.isCancelled {
            node.incomplete = true
            return node
        }
        let (entries, failure) = Self.read(path)
        if let failure {
            node.incomplete = true
            node.error = failure
        }

        var candidates: [(node: UsageNode, file: UsageFile, bucket: Int?, linked: FileIdentity?)] = []
        var directories: [UsageNode] = []
        var finished: [Int] = []
        var pending: [(index: Int, path: String, top: Int?)] = []
        let buckets = top == nil ? state.withLock { $0.topIndex } : [:]

        for entry in entries {
            let full = path == "/" ? "/" + entry.name : path + "/" + entry.name
            let bucket = top ?? buckets[entry.name]
            if !entry.isDirectory {
                var file = UsageNode(name: entry.name, isDirectory: false)
                file.fileCount = 1
                file.logicalBytes = Int64(entry.status.st_size)
                file.allocatedBytes = Int64(entry.status.st_blocks) * 512
                candidates.append((
                    file,
                    UsageFile(path: full, allocatedBytes: file.allocatedBytes, logicalBytes: file.logicalBytes),
                    bucket,
                    entry.isRegular && entry.status.st_nlink > 1 ? FileIdentity(entry.status) : nil
                ))
                if !entry.isRegular { candidates[candidates.count - 1].file = UsageFile(path: "", allocatedBytes: 0, logicalBytes: 0) }
                if top == nil, let bucket { finished.append(bucket) }
                continue
            }
            var child = UsageNode(name: entry.name, isDirectory: true)
            if full == skipPath {
                child.skipped = "other volumes"
            } else if !devices.contains(entry.status.st_dev) {
                child.skipped = "another volume"
            } else if entry.status.st_flags & UInt32(SF_DATALESS) != 0 {
                child.skipped = "not on this Mac"
            }
            if child.skipped == nil {
                pending.append((directories.count, full, bucket))
            } else if top == nil, let bucket {
                finished.append(bucket)
            }
            directories.append(child)
        }

        // One lock for the whole directory: the totals, the files with
        // several names, and the list of largest files. A file with more
        // than one name counts once for the scan.
        let limit = options.largestFiles
        var files: [UsageNode] = state.withLock { [candidates, finished] state in
            state.currentPath = path
            var counted: [UsageNode] = []
            counted.reserveCapacity(candidates.count)
            for candidate in candidates {
                if let identity = candidate.linked, !state.links.insert(identity).inserted { continue }
                counted.append(candidate.node)
                state.fileCount += 1
                state.allocatedBytes += candidate.node.allocatedBytes
                if let bucket = candidate.bucket { state.top[bucket].allocatedBytes += candidate.node.allocatedBytes }
                // An empty path marks an entry that is not a regular file.
                guard !candidate.file.path.isEmpty else { continue }
                if state.largest.count < limit {
                    state.largest.append(candidate.file)
                    if state.largest.count == limit { state.largest.sort(by: Self.fileOrder) }
                } else if Self.fileOrder(candidate.file, state.largest[limit - 1]) {
                    // The full list is kept sorted, so the last one is the smallest.
                    state.largest[limit - 1] = candidate.file
                    var index = limit - 1
                    while index > 0, Self.fileOrder(state.largest[index], state.largest[index - 1]) {
                        state.largest.swapAt(index, index - 1)
                        index -= 1
                    }
                }
            }
            for bucket in finished { state.top[bucket].done = true }
            return counted
        }

        // A subdirectory runs in its own task when a worker is free, and in
        // place when not, so that the depth of the tree cannot block the scan.
        await withTaskGroup(of: (Int, UsageNode).self) { group in
            for item in pending {
                let name = directories[item.index].name
                let isTop = top == nil
                if state.withLock({ state in
                    guard state.freeSlots > 0 else { return false }
                    state.freeSlots -= 1
                    return true
                }) {
                    group.addTask { [self] in
                        let node = await walk(item.path, name: name, top: item.top)
                        state.withLock { state in
                            state.freeSlots += 1
                            if isTop, let bucket = item.top { state.top[bucket].done = true }
                        }
                        return (item.index, node)
                    }
                } else {
                    directories[item.index] = await walk(item.path, name: name, top: item.top)
                    if isTop, let bucket = item.top {
                        state.withLock { $0.top[bucket].done = true }
                    }
                }
            }
            for await (index, child) in group {
                directories[index] = child
            }
        }

        for child in directories {
            node.allocatedBytes += child.allocatedBytes
            node.logicalBytes += child.logicalBytes
            node.fileCount += child.fileCount
            node.incomplete = node.incomplete || child.incomplete
        }
        files.sort(by: usageOrder)
        for (index, file) in files.enumerated() {
            node.allocatedBytes += file.allocatedBytes
            node.logicalBytes += file.logicalBytes
            node.fileCount += 1
            if index < options.filesPerDirectory {
                directories.append(file)
            } else {
                node.otherFileCount += 1
                node.otherAllocatedBytes += file.allocatedBytes
            }
        }
        node.children = directories.sorted(by: usageOrder)
        return node
    }
}
