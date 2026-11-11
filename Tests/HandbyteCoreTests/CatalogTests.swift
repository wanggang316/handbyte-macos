import Foundation
import Testing
@testable import HandbyteCore

/// Pin the bundled rule IDs so catalog changes are reviewed with the app.
private let expectedRuleIDs: Set<String> = [
    "apple-container",
    "arc-cache",
    "arc-profile-cache",
    "artifact:.build",
    "artifact:.dart_tool",
    "artifact:.gradle",
    "artifact:.mypy_cache",
    "artifact:.next",
    "artifact:.nuxt",
    "artifact:.parcel-cache",
    "artifact:.pytest_cache",
    "artifact:.ruff_cache",
    "artifact:.turbo",
    "artifact:.venv",
    "artifact:DerivedData",
    "artifact:Pods",
    "artifact:__pycache__",
    "artifact:build",
    "artifact:dist",
    "artifact:node_modules",
    "artifact:target",
    "artifact:venv",
    "brave-cache",
    "brave-profile-cache",
    "brew-cache",
    "bun-cache",
    "cargo-git",
    "cargo-registry",
    "chrome-cache",
    "chrome-profile-cache",
    "claude-vm",
    "cocoapods-cache",
    "codex",
    "composer-cache",
    "containers",
    "coresim-cache",
    "crash-reports",
    "cypress",
    "deno-cache",
    "device-firmware",
    "discord-cache",
    "docker",
    "downloads",
    "edge-cache",
    "edge-profile-cache",
    "firefox-cache",
    "go-build",
    "go-mod-cache",
    "gradle-cache",
    "ios-backups",
    "jetbrains",
    "library-caches",
    "library-logs",
    "mail-downloads",
    "maven-cache",
    "node-gyp-cache",
    "notion-cache",
    "npm-cache",
    "orbstack",
    "pip-cache",
    "playwright",
    "pnpm-store",
    "poetry-cache",
    "pub-cache",
    "rustup",
    "safari-cache",
    "slack-cache",
    "spotify-cache",
    "swiftpm-cache",
    "terraform-plugins",
    "trash",
    "vscode-cache",
    "xcode-archives",
    "xcode-derived",
    "xcode-device-logs",
    "xcode-devicesupport",
    "xcode-doc-cache",
    "xdg-cache",
    "yarn-cache",
]

@Test func catalogIDsMatchExpectedRules() {
    #expect(Set(Catalog.rules.map(\.id)) == expectedRuleIDs)
}

@Test func catalogRowCountsMatchGo() {
    #expect(Catalog.presets.count == 83)
    #expect(Catalog.projectArtifacts.count == 19)
}

@Test func catalogHasNoDuplicateRows() {
    let presetRows = Catalog.presets.map { "\($0.id)|\($0.pathTemplate ?? "")" }
    #expect(Set(presetRows).count == presetRows.count)

    let artifactNames = Catalog.projectArtifacts.compactMap(\.directoryName)
    #expect(Set(artifactNames).count == artifactNames.count)
    #expect(artifactNames.count == Catalog.projectArtifacts.count)
}

@Test func presetExpandsTildeAgainstInjectedHome() throws {
    let home = URL(filePath: "/Volumes/Test/alice", directoryHint: .isDirectory)

    let derived = try #require(Catalog.presets.first { $0.id == "xcode-derived" })
    #expect(derived.location(in: home)?.path == "/Volumes/Test/alice/Library/Developer/Xcode/DerivedData")
    #expect(derived.expandChildren == true)

    let deviceSupport = try #require(Catalog.presets.first { $0.pathTemplate == "~/Library/Developer/Xcode/iOS DeviceSupport" })
    #expect(deviceSupport.location(in: home)?.path == "/Volumes/Test/alice/Library/Developer/Xcode/iOS DeviceSupport")
    #expect(deviceSupport.expandChildren == true)

    let caches = try #require(Catalog.presets.first { $0.id == "library-caches" })
    #expect(caches.expandChildren == true)
}

@Test func everyPresetTemplateStartsWithTilde() {
    for rule in Catalog.presets {
        #expect(rule.pathTemplate?.hasPrefix("~/") == true, "\(rule.id)")
        #expect(rule.directoryName == nil, "\(rule.id)")
    }
}

@Test func artifactRulesUseArtifactPrefixAndNoPath() {
    let home = URL(filePath: "/Volumes/Test/alice", directoryHint: .isDirectory)
    for rule in Catalog.projectArtifacts {
        #expect(rule.id == "artifact:\(rule.directoryName ?? "")", "\(rule.id)")
        #expect(rule.category == .projectBuild, "\(rule.id)")
        #expect(rule.pathTemplate == nil, "\(rule.id)")
        #expect(rule.expandChildren == false, "\(rule.id)")
        #expect(rule.location(in: home) == nil, "\(rule.id)")
    }
}

@Test func defaultProjectRootsExpandAgainstInjectedHome() {
    let home = URL(filePath: "/Volumes/Test/alice", directoryHint: .isDirectory)
    #expect(Catalog.defaultProjectRoots == ["~/dev", "~/Projects", "~/Code", "~/workspace"])
    #expect(Catalog.defaultProjectRoots.map { PathTemplate.expand($0, home: home).path } == [
        "/Volumes/Test/alice/dev",
        "/Volumes/Test/alice/Projects",
        "/Volumes/Test/alice/Code",
        "/Volumes/Test/alice/workspace",
    ])
}

@Test func pathTemplateExpansionKeepsAbsolutePathsUntouched() {
    let home = URL(filePath: "/Volumes/Test/alice", directoryHint: .isDirectory)
    #expect(PathTemplate.expand("/opt/data", home: home).path == "/opt/data")
    #expect(PathTemplate.expand("~", home: home).path == "/Volumes/Test/alice")
}

@Test func selectedRulesCarryGoCategoryAndSafety() throws {
    let archives = try #require(Catalog.presets.first { $0.id == "xcode-archives" })
    #expect(archives.category == .xcode)
    #expect(archives.safety == .caution)

    let rustup = try #require(Catalog.presets.first { $0.id == "rustup" })
    #expect(rustup.safety == .review)
    #expect(rustup.expandChildren == true)

    let pycache = try #require(Catalog.projectArtifacts.first { $0.id == "artifact:__pycache__" })
    #expect(pycache.safety == .auto)

    let orbstack = try #require(Catalog.presets.first { $0.id == "orbstack" })
    #expect(orbstack.ownerBundleIDs == ["dev.kdrag0n.MacVirt"])
}

@Test func everyRuleHasSummaryAndRecovery() {
    for rule in Catalog.rules {
        #expect(!rule.summary.isEmpty, "\(rule.id)")
        #expect(!rule.recovery.isEmpty, "\(rule.id)")
    }
}

@Test func everyPresetFindsItsLocation() async throws {
    let home = try TemporaryHome()
    defer { home.cleanUp() }
    var want: [String: String] = [:]
    for rule in Catalog.presets {
        var relative = String(rule.pathTemplate!.dropFirst(2)).replacingOccurrences(of: "*", with: "Default")
        if rule.expandChildren { relative += "/child-of-\(rule.id)" }
        try home.writeFile(relative + "/data", size: 1)
        want[home.path(relative).fileSystemPath] = rule.id
    }
    var configuration = ScanConfiguration(home: home.url)
    configuration.minimumSize = 0
    configuration.skipProjectScan = true
    let result = await DiskScanner().collect(configuration)
    let got = Dictionary(result.candidates.map { ($0.url.fileSystemPath, $0.rule.id) }, uniquingKeysWith: { first, _ in first })
    for (path, id) in want {
        #expect(got[path] == id, "\(path)")
    }
}

@Test func catalogAreasAndDataClass() throws {
    #expect(Catalog.areas.map(\.id).first == "xcode")
    let derived = try #require(Catalog.presets.first { $0.id == "xcode-derived" })
    #expect(derived.area == "xcode" && derived.rebuildable && derived.ownerName == "Xcode")
    let backups = try #require(Catalog.presets.first { $0.id == "ios-backups" })
    #expect(!backups.rebuildable)
    let chrome = try #require(Catalog.presets.first { $0.id == "chrome-profile-cache" })
    #expect(chrome.ownerBundleIDs == ["com.google.Chrome"])
}
