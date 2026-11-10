import Foundation

/// Cleanups of files that belong to root: the rules of `system.json`, the
/// same file as `catalog/system.json` of the Go CLI. Measuring needs no
/// rights; cleaning runs one fixed find command for each rule as root.
public struct SystemRule: Sendable, Hashable, Decodable, Identifiable {
    public let id: String
    public let title: String
    public let root: String
    public let names: [String]
    public let minAgeDays: Int
    public let summary: String
    public let recovery: String

    public static let all: [SystemRule] = {
        struct File: Decodable {
            let version: Int
            let rules: [SystemRule]
        }
        guard let url = Bundle.module.url(forResource: "system", withExtension: "json", subdirectory: "catalog"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data), file.version == 1
        else { fatalError("catalog: system.json is missing or defective") }
        return file.rules
    }()

    /// The regular files the rule would remove under `root` (the rule root
    /// unless a test gives another), and whether a folder could not be read.
    public func measure(root override: String? = nil, now: Date = .now) -> (files: Int, bytes: Int64, partial: Bool) {
        let base = override ?? root
        // find -mtime +N takes files older than N whole days, so at least N+1 days.
        let limit = now.addingTimeInterval(-Double(minAgeDays + 1) * 86_400)
        let suffixes = names.map { String($0.dropFirst()) }
        var files = 0
        var bytes: Int64 = 0
        var partial = false
        guard let device = FileStatus(lstatPath: base)?.identity.dev else { return (0, 0, false) }
        var stack = [base]
        while let directory = stack.popLast() {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
                partial = true
                continue
            }
            for name in entries {
                let path = directory + "/" + name
                var status = stat()
                guard lstat(path, &status) == 0 else { partial = true; continue }
                switch status.st_mode & S_IFMT {
                case S_IFDIR:
                    // As find -xdev: stay on the volume of the root.
                    if FileIdentity(status).dev == device { stack.append(path) }
                case S_IFREG:
                    let modified = Date(timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec))
                    if suffixes.contains(where: { name.hasSuffix($0) }), modified < limit {
                        files += 1
                        bytes += Int64(status.st_blocks) * 512
                    }
                default:
                    continue
                }
            }
        }
        return (files, bytes, partial)
    }

    /// The fixed command as one shell line, every argument quoted. The same
    /// command as `system.Command` of the Go CLI.
    public var shellCommand: String {
        var args = ["/usr/bin/find", root, "-xdev", "-type", "f", "("]
        for (index, name) in names.enumerated() {
            if index > 0 { args.append("-o") }
            args += ["-name", name]
        }
        args += [")", "-mtime", "+\(minAgeDays)", "-print", "-delete"]
        return args.map { "'" + $0.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }.joined(separator: " ")
    }
}
