import Foundation
import Testing
@testable import HandbyteCore

/// One case of `Conformance/apps`, shared with the Go CLI.
private struct AppCase: Decodable {
    struct App: Decodable {
        let bundleID: String
        let name: String
        let zap: [String]
        let bundle: String?
        let team: String?
    }

    struct Expect: Decodable, Equatable {
        let path: String
        let `class`: String
        let confidence: String?
        let selected: Bool?
        let bundleID: String?
    }

    let name: String
    let app: App?
    let others: [String]?
    let withData: Bool?
    let installed: [String]?
    let installedNames: [String]?
    let otherTeams: [String]?
    let files: [String]
    let contents: [String: String]?
    let systemFiles: [String]?
    let systemContents: [String: String]?
    let expect: [Expect]
    let expectSystem: [Expect]?
}

private func makeTree(_ files: [String], _ contents: [String: String]?) throws -> TemporaryHome {
    let home = try TemporaryHome()
    for file in files { try home.writeFile(file, size: 1) }
    for (file, text) in contents ?? [:] {
        let url = home.url.appending(path: file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    return home
}

@Suite("App files")
struct AppFilesTests {
    @Test func matchesTheSharedConformanceCases() throws {
        let directory = try #require(Bundle.module.url(forResource: "Conformance", withExtension: nil))
            .appending(path: "apps", directoryHint: .isDirectory)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }
        #expect(names.count >= 4)
        for name in names {
            let value = try JSONDecoder().decode(AppCase.self, from: Data(contentsOf: directory.appending(path: name)))
            let home = try makeTree(value.files, value.contents)
            defer { home.cleanUp() }
            let prefix = home.url.fileSystemPath + "/"
            let got: [AppCase.Expect]
            if let app = value.app {
                let target = AppFiles.Target(
                    bundleID: app.bundleID, name: app.name, zap: app.zap, bundle: app.bundle, team: app.team,
                    otherTeams: value.otherTeams ?? []
                )
                got = AppFiles.related(home: home.url, target: target, others: value.others ?? [], withData: value.withData ?? false).map {
                    AppCase.Expect(path: String($0.url.fileSystemPath.dropFirst(prefix.count)), class: $0.fileClass,
                                   confidence: $0.confidence.rawValue, selected: $0.isSelected, bundleID: nil)
                }
                let root = try makeTree(value.systemFiles ?? [], value.systemContents)
                defer { root.cleanUp() }
                let rootPrefix = root.url.fileSystemPath + "/"
                let system = AppFiles.system(root: root.url, target: target, others: value.others ?? []).map {
                    AppCase.Expect(path: String($0.url.fileSystemPath.dropFirst(rootPrefix.count)), class: $0.fileClass,
                                   confidence: $0.confidence.rawValue, selected: nil, bundleID: nil)
                }
                #expect(system == (value.expectSystem ?? []), "\(name): system files")
            } else {
                got = AppFiles.leftovers(home: home.url, installed: value.installed ?? [], names: value.installedNames ?? []).map {
                    AppCase.Expect(path: String($0.url.fileSystemPath.dropFirst(prefix.count)), class: $0.fileClass,
                                   confidence: nil, selected: nil, bundleID: $0.bundleID)
                }
            }
            #expect(got == value.expect, "\(name): \(value.name)")
        }
    }

    @Test func inventoryReadsBundlesSourcesAndRunningState() throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        func make(_ app: String, _ id: String, _ extra: [String] = []) throws {
            let plist = #"<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>"# + id
                + #"</string><key>CFBundleShortVersionString</key><string>1.0</string></dict></plist>"#
            let info = home.url.appending(path: "Applications/\(app)/Contents/Info.plist")
            try FileManager.default.createDirectory(at: info.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(plist.utf8).write(to: info)
            for file in extra { try home.writeFile("Applications/\(app)/Contents/\(file)", size: 1) }
        }
        try make("Store.app", "com.example.store", ["_MASReceipt/receipt"])
        try make("Brewed.app", "com.example.brewed")
        try make("Plain.app", "com.example.plain")
        try make("Safari.app", "com.apple.Safari")
        try make(".Hidden.app", "com.example.hidden")
        try home.writeFile("Caskroom/brewed/.metadata/INSTALL_RECEIPT.json", size: 1)
        try Data(#"{"uninstall_artifacts":[{"app":["Brewed.app"]},{"zap":[{"trash":["~/Library/Caches/brewed"]}]}]}"#.utf8)
            .write(to: home.url.appending(path: "Caskroom/brewed/.metadata/INSTALL_RECEIPT.json"))

        var inventory = AppInventory(home: home.url, runningApps: StaticRunningAppsProbe(running: ["com.example.plain"]))
        inventory.roots = [home.path("Applications")]
        inventory.caskrooms = [home.path("Caskroom")]
        inventory.lastUsed = { _ in nil }
        let apps = Dictionary(uniqueKeysWithValues: inventory.list().map { ($0.name, $0) })

        #expect(Set(apps.keys) == ["Store", "Brewed", "Plain", "Safari"])
        #expect(apps["Store"]?.source == .appStore)
        #expect(apps["Brewed"]?.source == .homebrew && apps["Brewed"]?.caskToken == "brewed" && apps["Brewed"]?.zap == ["~/Library/Caches/brewed"])
        #expect(apps["Plain"]?.source == .direct && apps["Plain"]?.isRunning == true)
        #expect(apps["Safari"]?.isSystem == true)
        #expect(apps["Plain"]?.isUnused(now: .now) == false)
    }
}
