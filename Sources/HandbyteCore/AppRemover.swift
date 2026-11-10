import Foundation

/// Moves an app and its chosen files to the Trash, or only the files for a
/// reset. The same checks as `cleaner.Uninstall` of the Go CLI.
public struct AppRemover: Sendable {
    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case system(String)
        case homebrew(String, token: String)
        case running(String)
        case systemExtension(String)
        case notInRoot
        case changed

        public var description: String {
            switch self {
            case .system(let name): "\(name) is part of macOS and cannot be uninstalled."
            case .homebrew(let name, let token): "\(name) was installed with Homebrew. Run: brew uninstall --cask \(token)"
            case .running(let name): "\(name) is running. Quit it first."
            case .systemExtension(let name):
                "\(name) installs a system extension. Remove it with the app's own uninstaller, or turn the extension off in System Settings > General > Login Items & Extensions first."
            case .notInRoot: "The app is not directly in an application folder."
            case .changed: "The app changed since review. Open the list again."
            }
        }
    }

    public struct Plan: Sendable {
        public let app: InstalledApp
        /// The identity of the bundle when the plan was made.
        public let bundleIdentity: FileIdentity?
        /// False for a reset: the app stays.
        public let removesApp: Bool
        public let files: [AppFile]
        /// The identities of the files when the plan was made, by path.
        public let identities: [String: FileIdentity]

        public init(app: InstalledApp, removesApp: Bool, files: [AppFile]) {
            self.app = app
            self.removesApp = removesApp
            self.files = files
            bundleIdentity = FileStatus(lstatPath: app.url.fileSystemPath)?.identity
            var identities: [String: FileIdentity] = [:]
            for file in files {
                if let status = FileStatus(lstatPath: file.url.fileSystemPath), !status.isSymbolicLink {
                    identities[file.url.fileSystemPath] = status.identity
                }
            }
            self.identities = identities
        }
    }

    public struct Outcome: Sendable, Hashable {
        public enum Status: Sendable, Hashable {
            case moved(URL)
            case skipped(String)
            case failed(String)
        }

        public let url: URL
        public let bytes: Int64
        public let status: Status
    }

    private let trash: @Sendable (URL) throws -> URL
    private let now: @Sendable () -> Date

    public init(trash: @escaping @Sendable (URL) throws -> URL = Collector.systemTrash, now: @escaping @Sendable () -> Date = Date.init) {
        self.trash = trash
        self.now = now
    }

    /// Why the plan cannot run now, or nil.
    public func refusal(for plan: Plan, roots: [URL], runningApps: any RunningAppsProbe) -> Refusal? {
        let app = plan.app
        if app.isSystem { return .system(app.name) }
        guard plan.removesApp else { return nil }
        if let token = app.caskToken { return .homebrew(app.name, token: token) }
        if app.hasSystemExtension { return .systemExtension(app.name) }
        if runningApps.isRunning(bundleID: app.bundleID) { return .running(app.name) }
        let parent = app.url.deletingLastPathComponent().fileSystemPath
        guard roots.contains(where: { $0.fileSystemPath == parent }), app.url.pathExtension == "app" else { return .notInRoot }
        guard let identity = plan.bundleIdentity,
              FileStatus(lstatPath: app.url.fileSystemPath)?.identity == identity
        else { return .changed }
        return nil
    }

    /// Runs the plan. The app goes first; when it cannot move, nothing else
    /// moves. Each move is recorded with the rule ID `app:<bundle ID>`.
    public func remove(_ plan: Plan, roots: [URL], runningApps: any RunningAppsProbe, journal: (any Journal)?) throws(Refusal) -> [Outcome] {
        if let refusal = refusal(for: plan, roots: roots, runningApps: runningApps) { throw refusal }
        let ruleID = "app:\(plan.app.bundleID)"
        // One group, so that History puts the app and its files back together.
        let group = "app-" + JournalEntry.newID().prefix(8).lowercased()
        var outcomes: [Outcome] = []
        func move(_ url: URL, bytes: Int64, check: () -> String?) -> Bool {
            if let reason = check() {
                outcomes.append(Outcome(url: url, bytes: bytes, status: .skipped(reason)))
                return false
            }
            do {
                let destination = try trash(url)
                outcomes.append(Outcome(url: url, bytes: bytes, status: .moved(destination)))
                try? journal?.record(JournalEntry(timestamp: now(), action: .trash, outcome: .moved, ruleID: ruleID, bytes: bytes, path: url.fileSystemPath, detail: destination.fileSystemPath, group: group))
                return true
            } catch {
                outcomes.append(Outcome(url: url, bytes: bytes, status: .failed(error.localizedDescription)))
                try? journal?.record(JournalEntry(timestamp: now(), action: .trash, outcome: .failed, ruleID: ruleID, bytes: 0, path: url.fileSystemPath, detail: error.localizedDescription, group: group))
                return false
            }
        }
        if plan.removesApp {
            let moved = move(plan.app.url, bytes: plan.app.size) {
                refusal(for: plan, roots: roots, runningApps: runningApps)?.description
            }
            guard moved else { return outcomes }
        }
        for file in plan.files where file.isSelected {
            _ = move(file.url, bytes: file.size) {
                guard let identity = plan.identities[file.url.fileSystemPath],
                      FileStatus(lstatPath: file.url.fileSystemPath)?.identity == identity
                else { return "The file changed since review." }
                return nil
            }
        }
        return outcomes
    }
}
