import Foundation
import Testing
@testable import HandbyteCore

@Suite("App remover")
struct AppRemoverTests {
    private func fixture(_ home: TemporaryHome, running: Bool = false) throws -> (AppRemover, AppRemover.Plan, URL) {
        let root = try home.makeDirectory("Applications")
        try home.writeFile("Applications/Notes.app/Contents/Info.plist", size: 10)
        try home.writeFile("Library/Caches/com.example.Notes/c", size: 10)
        try home.writeFile("Library/Application Support/com.example.Notes/db", size: 10)
        let trash = try home.makeDirectory(".Trash")
        let remover = AppRemover(trash: { url in
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        })
        let app = InstalledApp(url: root.appending(path: "Notes.app"), name: "Notes", bundleID: "com.example.Notes", version: nil,
                               source: .direct, caskToken: nil, zap: [], isSystem: false, architectures: [])
        let files = AppFiles.related(home: home.url, bundleID: app.bundleID, name: app.name, zap: [], others: [], withData: false)
        return (remover, AppRemover.Plan(app: app, removesApp: true, files: files), root)
    }

    @Test func movesTheAppAndTheSelectedFiles() throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        let (remover, plan, root) = try fixture(home)
        let journal = MemoryJournalForApps()
        let outcomes = try remover.remove(plan, roots: [root], runningApps: StaticRunningAppsProbe(), journal: journal)
        #expect(outcomes.count == 2)
        #expect(!FileManager.default.fileExists(atPath: plan.app.url.path))
        #expect(!FileManager.default.fileExists(atPath: home.path("Library/Caches/com.example.Notes").path))
        // Data is not selected by default.
        #expect(FileManager.default.fileExists(atPath: home.path("Library/Application Support/com.example.Notes").path))
        #expect(journal.entries.map(\.ruleID) == ["app:com.example.Notes", "app:com.example.Notes"])
        // One group, so that one restore puts the app and its files back.
        #expect(Set(journal.entries.compactMap(\.group)).count == 1)
        #expect(journal.entries.allSatisfy { $0.group?.hasPrefix("app-") == true })
    }

    @Test func refusesSystemHomebrewRunningOutsideAndChangedApps() throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        let (remover, plan, root) = try fixture(home)
        let base = plan.app
        func variant(system: Bool = false, cask: String? = nil) -> AppRemover.Plan {
            AppRemover.Plan(app: InstalledApp(url: base.url, name: base.name, bundleID: base.bundleID, version: nil, source: .direct,
                                              caskToken: cask, zap: [], isSystem: system, architectures: []),
                            removesApp: true, files: plan.files)
        }
        #expect(remover.refusal(for: variant(system: true), roots: [root], runningApps: StaticRunningAppsProbe()) == .system("Notes"))
        #expect(remover.refusal(for: variant(cask: "notes"), roots: [root], runningApps: StaticRunningAppsProbe()) == .homebrew("Notes", token: "notes"))
        #expect(remover.refusal(for: plan, roots: [root], runningApps: StaticRunningAppsProbe(running: ["com.example.Notes"])) == .running("Notes"))
        #expect(remover.refusal(for: plan, roots: [URL(filePath: "/Applications")], runningApps: StaticRunningAppsProbe()) == .notInRoot)
        try FileManager.default.removeItem(at: base.url)
        try home.writeFile("Applications/Notes.app/Contents/Info.plist", size: 10)
        #expect(remover.refusal(for: plan, roots: [root], runningApps: StaticRunningAppsProbe()) == .changed)
        var withExtension = variant().app
        withExtension.hasSystemExtension = true
        #expect(remover.refusal(for: AppRemover.Plan(app: withExtension, removesApp: true, files: []), roots: [root], runningApps: StaticRunningAppsProbe()) == .systemExtension("Notes"))
        // A reset keeps the app, so a Homebrew app may lose its files.
        let reset = AppRemover.Plan(app: variant(cask: "notes").app, removesApp: false, files: plan.files)
        #expect(remover.refusal(for: reset, roots: [root], runningApps: StaticRunningAppsProbe()) == nil)
    }
}

final class MemoryJournalForApps: Journal, @unchecked Sendable {
    var entries: [JournalEntry] = []
    func record(_ entry: JournalEntry) throws { entries.append(entry) }
}
