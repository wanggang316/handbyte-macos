import Foundation

/// Cleanups of files that belong to root: the rules of `system.json`, the
/// same file as `catalog/system.json` of the Go CLI. Measuring needs no
/// rights; cleaning runs one fixed command for each rule as root: a find
/// command, or for a command rule a tool of macOS that the CLI catalog
/// validation allows.
public struct SystemRule: Sendable, Hashable, Decodable, Identifiable {
    public let id: String
    public let title: String
    public let root: String
    public let names: [String]
    public let minAgeDays: Int
    public let summary: String
    public let recovery: String
    /// "review" rules need their own confirmation; Smart Clean takes only
    /// the other rules.
    public let tier: String?
    public let command: [String]?
    public let measure: [String]?

    enum CodingKeys: String, CodingKey {
        case id, title, root, names, minAgeDays, summary, recovery, tier, command, measure
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        root = try c.decode(String.self, forKey: .root)
        names = try c.decodeIfPresent([String].self, forKey: .names) ?? []
        minAgeDays = try c.decodeIfPresent(Int.self, forKey: .minAgeDays) ?? 0
        summary = try c.decode(String.self, forKey: .summary)
        recovery = try c.decode(String.self, forKey: .recovery)
        tier = try c.decodeIfPresent(String.self, forKey: .tier)
        command = try c.decodeIfPresent([String].self, forKey: .command)
        measure = try c.decodeIfPresent([String].self, forKey: .measure)
    }

    public var needsReview: Bool { tier == "review" }

    /// The only tools a command rule can run; the same list as the Go CLI.
    static let allowedCommands: [[String]] = [["/usr/bin/log", "erase", "--all"]]

    public static let all: [SystemRule] = {
        struct File: Decodable {
            let version: Int
            let rules: [SystemRule]
        }
        guard let url = Bundle.module.url(forResource: "system", withExtension: "json", subdirectory: "catalog"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data), file.version == 1,
              file.rules.allSatisfy({ $0.command.map { allowedCommands.contains($0) && $0.count > 0 } ?? true })
        else { fatalError("catalog: system.json is missing or defective") }
        return file.rules
    }()

    /// The regular files the rule would remove under `root` (the rule root
    /// unless a test gives another), and whether a folder could not be read.
    public func measure(root override: String? = nil, now: Date = .now) -> (files: Int, bytes: Int64, partial: Bool) {
        if let folders = measure, command != nil {
            var total = (files: 0, bytes: Int64(0), partial: false)
            for folder in override.map({ [$0] }) ?? folders {
                let part = Self.walk(folder) { _, _ in true }
                total = (total.files + part.files, total.bytes + part.bytes, total.partial || part.partial)
            }
            return total
        }
        let base = override ?? root
        // find -mtime +N takes files older than N whole days, so at least N+1 days.
        let limit = now.addingTimeInterval(-Double(minAgeDays + 1) * 86_400)
        let suffixes = names.map { String($0.dropFirst()) }
        return Self.walk(base) { name, status in
            let modified = Date(timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec))
            return suffixes.contains(where: { name.hasSuffix($0) }) && modified < limit
        }
    }

    /// Counts the regular files below `base` that `take` accepts, on the
    /// volume of `base` (as find -xdev).
    static func walk(_ base: String, take: (String, stat) -> Bool) -> (files: Int, bytes: Int64, partial: Bool) {
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
                    if FileIdentity(status).dev == device { stack.append(path) }
                case S_IFREG:
                    if take(name, status) {
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
        if let command { return command.map { "'" + $0 + "'" }.joined(separator: " ") }
        var args = ["/usr/bin/find", root, "-xdev", "-type", "f", "("]
        for (index, name) in names.enumerated() {
            if index > 0 { args.append("-o") }
            args += ["-name", name]
        }
        args += [")", "-mtime", "+\(minAgeDays)", "-print", "-delete"]
        return args.map { "'" + $0.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }.joined(separator: " ")
    }
}
