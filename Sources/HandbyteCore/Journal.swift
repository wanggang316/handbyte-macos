// Operations journal: the audit trail of every file system change the app
// made or tried to make.
//
// The app and the Go CLI write one journal,
// `~/Library/Application Support/handbyte/actions.jsonl`. Each line is one
// JSON record of one action; the last line of an ID is the present state of
// that action. The keys are in `Conformance/README.md` ("journal"), and the
// shared cases check that both products read the same state. A writer
// appends one complete line with one write(2) call and refuses to write
// after a line without its newline, because the CLI then refuses the file.
//
// The app wrote `~/Library/Logs/handbyte/operations.log` (seven
// tab-separated fields) before. That file is read for History only; its
// moves cannot be restored, because it has no Trash identity.

import Foundation

/// One applied (or attempted) file system change.
public struct JournalEntry: Sendable, Hashable {
    public enum Outcome: String, Sendable, Codable {
        case moved
        case removed
        case failed
        case restored
    }

    /// The action ID. A restore writes a new state of the same ID.
    public var id: String
    public var timestamp: Date
    public var action: CleanAction
    public var outcome: Outcome
    public var ruleID: String
    public var bytes: Int64
    public var path: String
    /// Trash destination for `moved` and `restored`, error text for
    /// `failed`, nil otherwise.
    public var detail: String?
    /// The actions of one uninstall share a group, so that one restore puts
    /// all of them back.
    public var group: String?
    /// Device and inode of the item in the Trash. A restore needs it.
    public var trashIdentity: FileIdentity?

    public init(
        id: String = JournalEntry.newID(), timestamp: Date, action: CleanAction, outcome: Outcome, ruleID: String,
        bytes: Int64, path: String, detail: String?, group: String? = nil, trashIdentity: FileIdentity? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
        self.outcome = outcome
        self.ruleID = ruleID
        self.bytes = bytes
        self.path = path
        self.detail = detail
        self.group = group
        self.trashIdentity = trashIdentity
    }

    public static func newID() -> String {
        UUID().uuidString
    }

    /// A move that a restore can undo: it has a Trash place and identity.
    public var canRestore: Bool {
        outcome == .moved && detail != nil && trashIdentity != nil
    }
}

public protocol Journal: Sendable {
    func record(_ entry: JournalEntry) throws
}

/// The journal file that the app and the CLI share.
public struct OperationsJournal: Journal {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case unterminatedRecord
        case notARegularFile

        public var description: String {
            switch self {
            case .unterminatedRecord: "The journal ends with an incomplete record."
            case .notARegularFile: "The journal is not a regular file."
            }
        }
    }

    public let fileURL: URL
    /// The journal of earlier app versions, read for History only.
    public let legacyURL: URL?

    public init(fileURL: URL, legacyURL: URL? = nil) {
        self.fileURL = fileURL
        self.legacyURL = legacyURL
    }

    /// `~/Library/Application Support/handbyte/actions.jsonl` for the given home.
    public static func defaultURL(home: URL) -> URL {
        home.appending(path: "Library/Application Support/handbyte/actions.jsonl")
    }

    /// `~/Library/Logs/handbyte/operations.log`, written by earlier versions.
    public static func legacyURL(home: URL) -> URL {
        home.appending(path: "Library/Logs/handbyte/operations.log")
    }

    public static func standard(home: URL) -> OperationsJournal {
        OperationsJournal(fileURL: defaultURL(home: home), legacyURL: legacyURL(home: home))
    }

    /// The present state of each action, in the order of its first record,
    /// after the entries of the legacy file. Actions that changed nothing
    /// (skipped, previewed, cancelled) are left out. Lines that do not
    /// decode are left out. No file means no entries.
    public func entries() throws -> [JournalEntry] {
        var result: [JournalEntry] = []
        if let legacyURL, let text = try? String(contentsOf: legacyURL, encoding: .utf8) {
            result = text.split(separator: "\n").enumerated().compactMap { JournalEntry(legacyLine: String($1), id: "legacy:\($0)") }
        }
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return result }
        let data = try Data(contentsOf: fileURL)
        var order: [String] = []
        var states: [String: JournalRecord] = [:]
        let decoder = JSONDecoder()
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let record = try? decoder.decode(JournalRecord.self, from: Data(line)) else { continue }
            if states[record.id] == nil { order.append(record.id) }
            states[record.id] = record
        }
        result += order.compactMap { states[$0]?.entry }
        return result
    }

    public func record(_ entry: JournalEntry) throws {
        var entry = entry
        if entry.outcome == .moved, entry.trashIdentity == nil, let detail = entry.detail {
            entry.trashIdentity = FileStatus(lstatPath: detail)?.identity
        }
        var line = try JSONEncoder.journal.encode(JournalRecord(entry))
        line.append(UInt8(ascii: "\n"))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try append(line)
    }

    private func append(_ line: Data) throws {
        let fd = open(fileURL.fileSystemPath, O_RDWR | O_CREAT | O_APPEND | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        var status = stat()
        guard fstat(fd, &status) == 0, status.st_mode & S_IFMT == S_IFREG else { throw Failure.notARegularFile }
        if status.st_size > 0 {
            var last: UInt8 = 0
            guard pread(fd, &last, 1, status.st_size - 1) == 1, last == UInt8(ascii: "\n") else {
                throw Failure.unterminatedRecord
            }
        }
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == line.count else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}

/// One line of the shared journal. The keys are the field names of the Go
/// CLI record; keys that only the CLI uses are not written.
struct JournalRecord: Codable {
    struct Identity: Codable {
        var device: UInt64
        var inode: UInt64

        enum CodingKeys: String, CodingKey {
            case device = "Device"
            case inode = "Inode"
        }
    }

    var id: String
    var path: String
    var status: String
    var destination: String?
    var message: String?
    var trashIdentity: Identity?
    var moved: Int64?
    var freed: Int64?
    var startedAt: String?
    var endedAt: String?
    var group: String?
    var rule: String?
    var tool: String?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case path = "Path"
        case status = "Status"
        case destination = "Destination"
        case message = "Message"
        case trashIdentity = "TrashIdentity"
        case moved = "Moved"
        case freed = "Freed"
        case startedAt = "StartedAt"
        case endedAt = "EndedAt"
        case group = "Group"
        case rule = "Rule"
        case tool = "Tool"
    }

    init(_ entry: JournalEntry) {
        id = entry.id
        path = entry.path
        group = entry.group
        rule = entry.ruleID
        tool = "app"
        startedAt = JournalTime.string(entry.timestamp)
        endedAt = startedAt
        // The CLI reads the device as Go does: st_dev is a signed 32-bit
        // value, widened with its sign.
        trashIdentity = entry.trashIdentity.map {
            Identity(device: UInt64(bitPattern: Int64(Int32(truncatingIfNeeded: $0.dev))), inode: $0.ino)
        }
        switch entry.outcome {
        case .moved, .restored:
            status = entry.outcome == .moved ? "trashed" : "restored"
            destination = entry.detail
            moved = entry.bytes
        case .removed:
            status = "removed"
            freed = entry.bytes
        case .failed:
            status = "failed"
            message = entry.detail
        }
    }

    /// The entry that History shows, or nil for an action that changed nothing.
    var entry: JournalEntry? {
        let outcome: JournalEntry.Outcome
        var detail: String?
        switch status {
        case "trashed":
            outcome = .moved
            detail = destination.flatMap { $0.isEmpty ? nil : $0 }
        case "restored":
            outcome = .restored
            detail = destination
        case "removed":
            outcome = .removed
        case "failed":
            outcome = .failed
            detail = message
        case "started":
            outcome = .failed
            detail = "The action did not finish. Check the item in Finder."
        case "restoring":
            outcome = .failed
            detail = "The restore did not finish. Check the Trash in Finder."
        default:
            return nil
        }
        let timestamp = [endedAt, startedAt].compactMap { $0.flatMap(JournalTime.date) }.first { $0.timeIntervalSince1970 > 0 }
        // The CLI writes zero for an unknown identity.
        let identity = trashIdentity.flatMap { $0.inode == 0 ? nil : FileIdentity(dev: UInt64(UInt32(truncatingIfNeeded: $0.device)), ino: $0.inode) }
        return JournalEntry(
            id: id, timestamp: timestamp ?? .distantPast, action: status == "removed" ? .removePermanently : .trash,
            outcome: outcome, ruleID: rule ?? "", bytes: (moved ?? 0) + (freed ?? 0), path: path, detail: detail,
            group: group.flatMap { $0.isEmpty ? nil : $0 }, trashIdentity: identity
        )
    }
}

/// RFC 3339 times as the CLI writes and reads them: fractions of any length
/// and a zone offset.
enum JournalTime {
    static func string(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    static func date(_ text: String) -> Date? {
        var text = text
        var fraction = 0.0
        if let dot = text.firstIndex(of: "."),
           let end = text[dot...].dropFirst().firstIndex(where: { !$0.isNumber }) {
            fraction = Double("0" + text[dot..<end]) ?? 0
            text.removeSubrange(dot..<end)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text).map { $0.addingTimeInterval(fraction) }
    }
}

extension JSONEncoder {
    static let journal: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()
}

extension JournalEntry {
    /// Reads a line of the legacy tab-separated journal. Nil for a line in
    /// another format.
    init?(legacyLine line: String, id: String) {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 7,
              let timestamp = try? Date(fields[0], strategy: .iso8601),
              let outcome = Outcome(rawValue: fields[2]),
              let bytes = Int64(fields[4])
        else { return nil }
        let action: CleanAction
        switch fields[1] {
        case "trash": action = .trash
        case "removePermanently": action = .removePermanently
        case "preview": action = .preview
        default: return nil
        }
        let detail = Self.unescape(fields[6])
        self.init(
            id: id, timestamp: timestamp, action: action, outcome: outcome, ruleID: fields[3],
            bytes: bytes, path: Self.unescape(fields[5]), detail: detail.isEmpty ? nil : detail
        )
    }

    private static func unescape(_ field: String) -> String {
        var out = ""
        var escaping = false
        for character in field {
            if escaping {
                switch character {
                case "t": out.append("\t")
                case "n": out.append("\n")
                case "r": out.append("\r")
                default: out.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                out.append(character)
            }
        }
        return out
    }
}
