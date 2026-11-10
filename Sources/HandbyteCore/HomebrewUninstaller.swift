import Foundation

/// Runs `brew uninstall --cask <token>` for an app that Homebrew installed,
/// so that the Homebrew state stays correct. Homebrew removes the app
/// itself; it does not go to the Trash and cannot be restored.
public struct HomebrewUninstaller: Sendable {
    public struct Result: Sendable, Equatable {
        public let succeeded: Bool
        /// The last lines of the output of brew.
        public let output: String
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case noBrew
        case badToken
        case running(String)

        public var description: String {
            switch self {
            case .noBrew: "Homebrew was not found in /opt/homebrew or /usr/local."
            case .badToken: "The cask name is not valid."
            case .running(let name): "\(name) is running. Quit it first."
            }
        }
    }

    public let brew: URL?

    public init(brew: URL? = HomebrewUninstaller.findBrew()) {
        self.brew = brew
    }

    public static func findBrew() -> URL? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(filePath: $0) }
    }

    /// A cask token is lower case letters, digits, `-`, `_`, `@`, `.` and `+`.
    static func isValidToken(_ token: String) -> Bool {
        !token.isEmpty && !token.hasPrefix("-") && token.wholeMatch(of: /[a-z0-9@._+\-]+/) != nil
    }

    /// Runs brew and waits for it. The app must not run.
    public func uninstall(
        _ app: InstalledApp, runningApps: any RunningAppsProbe, journal: (any Journal)?, now: Date = .now
    ) throws(Failure) -> Result {
        guard let brew else { throw .noBrew }
        guard let token = app.caskToken, Self.isValidToken(token) else { throw .badToken }
        if runningApps.isRunning(bundleID: app.bundleID) { throw .running(app.name) }
        let process = Process()
        process.executableURL = brew
        process.arguments = ["uninstall", "--cask", token]
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return Result(succeeded: false, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        let output = text.split(separator: "\n").suffix(8).joined(separator: "\n")
        let succeeded = process.terminationStatus == 0
        try? journal?.record(JournalEntry(
            timestamp: now, action: .removePermanently, outcome: succeeded ? .removed : .failed,
            ruleID: "app:\(app.bundleID)", bytes: succeeded ? app.size : 0, path: app.url.fileSystemPath,
            detail: succeeded ? nil : "brew uninstall --cask \(token) failed: \(output)"
        ))
        return Result(succeeded: succeeded, output: output)
    }
}
