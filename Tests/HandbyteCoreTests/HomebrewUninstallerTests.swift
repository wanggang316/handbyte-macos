import Foundation
import Testing
@testable import HandbyteCore

private final class Recorder: Journal, @unchecked Sendable {
    var entries: [JournalEntry] = []
    func record(_ entry: JournalEntry) throws { entries.append(entry) }
}

@Suite("Homebrew uninstaller")
struct HomebrewUninstallerTests {
    /// A stand-in for brew that writes its arguments and exits with `status`.
    private func fakeBrew(_ home: TemporaryHome, status: Int) throws -> (URL, URL) {
        let log = home.url.appending(path: "args.txt")
        let script = home.url.appending(path: "brew")
        try Data("#!/bin/sh\necho \"$@\" > '\(log.fileSystemPath)'\necho done\nexit \(status)\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.fileSystemPath)
        return (script, log)
    }

    private func app(cask: String?) -> InstalledApp {
        InstalledApp(url: URL(filePath: "/Applications/Notes.app"), name: "Notes", bundleID: "com.example.Notes", version: nil,
                     source: .homebrew, caskToken: cask, zap: [], isSystem: false, architectures: [])
    }

    @Test func runsBrewForTheCaskAndRecordsTheRemoval() throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        let (brew, log) = try fakeBrew(home, status: 0)
        let journal = Recorder()

        let result = try HomebrewUninstaller(brew: brew).uninstall(app(cask: "notes"), runningApps: StaticRunningAppsProbe(), journal: journal)

        #expect(result.succeeded)
        #expect(try String(contentsOf: log, encoding: .utf8) == "uninstall --cask notes\n")
        #expect(journal.entries.map(\.outcome) == [.removed])
        #expect(journal.entries.map(\.ruleID) == ["app:com.example.Notes"])
    }

    @Test func aFailureOfBrewIsRecordedWithItsOutput() throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        let (brew, _) = try fakeBrew(home, status: 1)
        let journal = Recorder()

        let result = try HomebrewUninstaller(brew: brew).uninstall(app(cask: "notes"), runningApps: StaticRunningAppsProbe(), journal: journal)

        #expect(!result.succeeded)
        #expect(result.output == "done")
        #expect(journal.entries.map(\.outcome) == [.failed])
    }

    @Test func refusesABadTokenARunningAppAndNoBrew() throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        let (brew, log) = try fakeBrew(home, status: 0)
        let uninstaller = HomebrewUninstaller(brew: brew)
        #expect(throws: HomebrewUninstaller.Failure.badToken) { try uninstaller.uninstall(app(cask: "--force"), runningApps: StaticRunningAppsProbe(), journal: nil) }
        #expect(throws: HomebrewUninstaller.Failure.badToken) { try uninstaller.uninstall(app(cask: nil), runningApps: StaticRunningAppsProbe(), journal: nil) }
        #expect(throws: HomebrewUninstaller.Failure.running("Notes")) {
            try uninstaller.uninstall(app(cask: "notes"), runningApps: StaticRunningAppsProbe(running: ["com.example.Notes"]), journal: nil)
        }
        #expect(throws: HomebrewUninstaller.Failure.noBrew) { try HomebrewUninstaller(brew: nil).uninstall(app(cask: "notes"), runningApps: StaticRunningAppsProbe(), journal: nil) }
        #expect(!FileManager.default.fileExists(atPath: log.path))
    }
}
