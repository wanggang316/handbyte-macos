import CoreServices
import Foundation
import Security

/// The content of `apps.json`: where an app keeps its files, and the rules
/// that keep the matching exact. The same file as `catalog/apps.json` of the
/// Go CLI.
public struct AppCatalog: Sendable, Decodable {
    public struct Location: Sendable, Decodable {
        public let path: String
        public let `class`: String
    }

    public let version: Int
    public let applicationRoots: [String]
    public let locations: [Location]
    /// Places outside the home folder. Their files belong to root: they are
    /// listed, never selected and never removed.
    public let systemLocations: [Location]
    /// Folders of launchd property lists. A list that names a path inside
    /// the app bundle belongs to the app.
    public let launchdFolders: [String]
    public let leftoverRoots: [String]
    public let genericNames: [String]
    public let protectedPrefixes: [String]
    public let leftoverIgnorePrefixes: [String]

    public static let shared: AppCatalog = {
        guard let url = Bundle.module.url(forResource: "apps", withExtension: "json", subdirectory: "catalog"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(AppCatalog.self, from: data),
              catalog.version == 1
        else {
            // A defective catalog is a build defect, not a runtime condition.
            fatalError("catalog: apps.json is missing or defective")
        }
        return catalog
    }()

    public func isProtected(_ bundleID: String) -> Bool {
        protectedPrefixes.contains { bundleID.hasPrefix($0) }
    }
}

/// One installed application bundle.
public struct InstalledApp: Sendable, Hashable, Identifiable {
    public enum Source: String, Sendable, Hashable {
        case appStore = "App Store"
        case homebrew = "Homebrew"
        case setapp = "Setapp"
        case direct = "Direct"
    }

    public let url: URL
    public let name: String
    public let bundleID: String
    public let version: String?
    public var size: Int64 = 0
    /// Nil when Spotlight has no date; that is not the same as "never opened".
    public var lastUsed: Date?
    public let source: Source
    public let caskToken: String?
    /// Paths the Homebrew cask names for a full removal.
    public let zap: [String]
    public var isRunning = false
    public let isSystem: Bool
    public let architectures: [String]
    /// The signing team, or nil for an app without one.
    public var team: String?
    /// The app installs a system extension. Moving it to the Trash leaves
    /// the extension active, so an uninstall is refused.
    public var hasSystemExtension = false

    public var id: String { url.fileSystemPath }

    public init(
        url: URL, name: String, bundleID: String, version: String?, source: Source, caskToken: String?,
        zap: [String], isSystem: Bool, architectures: [String]
    ) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.source = source
        self.caskToken = caskToken
        self.zap = zap
        self.isSystem = isSystem
        self.architectures = architectures
    }

    /// Not opened for six months. An app without a known date is not unused.
    public func isUnused(now: Date) -> Bool {
        guard let lastUsed else { return false }
        return now.timeIntervalSince(lastUsed) > 182 * 24 * 3600
    }
}

/// Lists the apps and reads their facts. It reads only.
public struct AppInventory: Sendable {
    public var roots: [URL]
    public var caskrooms: [URL]
    public var runningApps: any RunningAppsProbe
    /// Reads the last-used date; nil means unknown.
    public var lastUsed: @Sendable (URL) -> Date?

    public init(home: URL, runningApps: any RunningAppsProbe) {
        roots = AppCatalog.shared.applicationRoots.map { PathTemplate.expand($0, home: home) }
        caskrooms = [URL(filePath: "/opt/homebrew/Caskroom"), URL(filePath: "/usr/local/Caskroom")]
        self.runningApps = runningApps
        lastUsed = AppInventory.spotlightLastUsed
    }

    /// The apps directly in the roots, sorted by name, without sizes. Nested
    /// apps, hidden helpers and symbolic links are left out.
    public func list() -> [InstalledApp] {
        let casks = Self.caskApps(caskrooms)
        var apps: [InstalledApp] = []
        for root in roots {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root.fileSystemPath)) ?? []
            for name in names where name.hasSuffix(".app") && !name.hasPrefix(".") {
                let url = root.appending(path: name, directoryHint: .isDirectory)
                // The Info.plist is read directly: Bundle caches by path and
                // can return a stale or empty dictionary.
                guard let status = FileStatus(lstatPath: url.fileSystemPath), status.isDirectory,
                      let data = try? Data(contentsOf: url.appending(path: "Contents/Info.plist")),
                      let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let bundleID = info["CFBundleIdentifier"] as? String
                else { continue }
                let receipt = url.appending(path: "Contents/_MASReceipt/receipt").fileSystemPath
                var source: InstalledApp.Source = FileStatus(lstatPath: receipt) != nil ? .appStore : .direct
                if url.fileSystemPath.contains("/Setapp/") { source = .setapp }
                let cask = casks[name]
                if cask != nil { source = .homebrew }
                let archs = (Bundle(url: url)?.executableArchitectures ?? []).compactMap { number -> String? in
                    switch number.intValue {
                    case NSBundleExecutableArchitectureARM64: "arm64"
                    case NSBundleExecutableArchitectureX86_64: "x86_64"
                    default: nil
                    }
                }
                var app = InstalledApp(
                    url: url,
                    name: String(name.dropLast(4)),
                    bundleID: bundleID,
                    version: info["CFBundleShortVersionString"] as? String,
                    source: source,
                    caskToken: cask?.token,
                    zap: cask?.zap ?? [],
                    isSystem: AppCatalog.shared.isProtected(bundleID),
                    architectures: archs
                )
                app.lastUsed = lastUsed(url)
                app.team = Self.signingTeam(url)
                let extensions = url.appending(path: "Contents/Library/SystemExtensions").fileSystemPath
                app.hasSystemExtension = !((try? FileManager.default.contentsOfDirectory(atPath: extensions)) ?? []).isEmpty
                app.isRunning = runningApps.isRunning(bundleID: bundleID)
                apps.append(app)
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Spotlight sets kMDItemLastUsedDate only for launches through
    /// LaunchServices, so nil means "unknown".
    public static let spotlightLastUsed: @Sendable (URL) -> Date? = { url in
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// The team identifier of the code signature, read without a check of
    /// the signature.
    public static func signingTeam(_ url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any]
        else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private struct Cask {
        let token: String
        let zap: [String]
    }

    /// Reads the install receipts of the Homebrew casks: the app names they
    /// installed and the paths their zap stanza names.
    private static func caskApps(_ roots: [URL]) -> [String: Cask] {
        var out: [String: Cask] = [:]
        for root in roots {
            let tokens = (try? FileManager.default.contentsOfDirectory(atPath: root.fileSystemPath)) ?? []
            for token in tokens {
                let receipt = root.appending(path: "\(token)/.metadata/INSTALL_RECEIPT.json")
                guard let data = try? Data(contentsOf: receipt),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let artifacts = json["uninstall_artifacts"] as? [[String: Any]]
                else { continue }
                var appNames: [String] = []
                var zap: [String] = []
                for artifact in artifacts {
                    for case let name as String in artifact["app"] as? [Any] ?? [] {
                        appNames.append(URL(filePath: name).lastPathComponent)
                    }
                    for stanza in artifact["zap"] as? [[String: Any]] ?? [] {
                        for key in ["trash", "delete"] {
                            if let list = stanza[key] as? [String] { zap += list }
                            if let one = stanza[key] as? String { zap.append(one) }
                        }
                    }
                }
                for name in appNames { out[name] = Cask(token: token, zap: zap) }
            }
        }
        return out
    }
}

/// A file or a folder that an app keeps in the home folder.
public struct AppFile: Sendable, Hashable, Identifiable {
    public enum Confidence: String, Sendable, Hashable, Comparable {
        case low, medium, high

        public static func < (lhs: Self, rhs: Self) -> Bool {
            let order: [Self] = [.low, .medium, .high]
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }
    }

    public let url: URL
    public let fileClass: String
    public let confidence: Confidence
    /// The default choice for an uninstall.
    public var isSelected: Bool
    public let isDirectory: Bool
    /// Outside the home folder and owned by root: listed, not removed.
    public let isSystem: Bool
    public var size: Int64 = 0

    public var id: String { url.fileSystemPath }

    public init(url: URL, fileClass: String, confidence: Confidence, isSelected: Bool, isDirectory: Bool, isSystem: Bool = false) {
        self.url = url
        self.fileClass = fileClass
        self.confidence = confidence
        self.isSelected = isSelected
        self.isDirectory = isDirectory
        self.isSystem = isSystem
    }
}

/// Finds the files of an app and the data of apps that are gone, by the
/// rules of the app catalog. The same rules as `internal/apps` of the Go CLI;
/// the conformance cases keep them equal.
private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) && count > suffix.count ? String(dropLast(suffix.count)) : self
    }
}

public enum AppFiles {
    static func isValidBundleID(_ id: String) -> Bool {
        id.count >= 5 && id.wholeMatch(of: /^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9_-]*)+$/) != nil
    }

    static func isSelectedByDefault(_ fileClass: String, _ confidence: AppFile.Confidence, withData: Bool) -> Bool {
        if confidence == .low { return false }
        switch fileClass {
        case "data": return withData
        case "settings": return confidence == .high || withData
        default: return true
        }
    }

    /// The facts of an app that the matching needs. `bundle` is the path of
    /// the .app folder; `otherTeams` are the signing teams of the other
    /// installed apps.
    public struct Target: Sendable {
        public var bundleID: String
        public var name: String
        public var zap: [String]
        public var bundle: String?
        public var team: String?
        public var otherTeams: [String]

        public init(bundleID: String, name: String, zap: [String] = [], bundle: String? = nil, team: String? = nil, otherTeams: [String] = []) {
            self.bundleID = bundleID
            self.name = name
            self.zap = zap
            self.bundle = bundle
            self.team = team
            self.otherTeams = otherTeams
        }
    }

    /// The files of an app in the home folder, in path order. `others` are
    /// the bundle IDs of the other installed apps.
    public static func related(
        home: URL, bundleID: String, name: String, zap: [String], others: [String], withData: Bool
    ) -> [AppFile] {
        related(home: home, target: Target(bundleID: bundleID, name: name, zap: zap), others: others, withData: withData)
    }

    public static func related(home: URL, target: Target, others: [String], withData: Bool) -> [AppFile] {
        let catalog = AppCatalog.shared
        if catalog.isProtected(target.bundleID) { return [] }
        var found: [String: AppFile] = [:]

        func add(_ path: String, _ fileClass: String, _ confidence: AppFile.Confidence) {
            guard let status = FileStatus(lstatPath: path), !status.isSymbolicLink else { return }
            if belongsToOther(URL(filePath: path).lastPathComponent, own: target.bundleID, others: others) { return }
            if let old = found[path], old.confidence >= confidence { return }
            found[path] = AppFile(
                url: URL(filePath: path), fileClass: fileClass, confidence: confidence,
                isSelected: isSelectedByDefault(fileClass, confidence, withData: withData), isDirectory: status.isDirectory
            )
        }

        matchLocations(catalog.locations, expand: { PathTemplate.expand($0, home: home).fileSystemPath }, target: target, add: add)
        for folder in catalog.launchdFolders where folder.hasPrefix("~/") {
            for path in launchdOwned(PathTemplate.expand(folder, home: home).fileSystemPath, target: target, root: "").lists {
                add(path, "state", .high)
            }
        }
        let library = home.appending(path: "Library").fileSystemPath + "/"
        for entry in target.zap where entry.hasPrefix("~/") && !entry.contains(where: { "*?[".contains($0) }) {
            let path = PathTemplate.expand(entry, home: home).fileSystemPath
            guard path.hasPrefix(library) else { continue }
            add(path, fileClass(of: path, home: home), .medium)
        }
        return found.values.sorted { $0.url.fileSystemPath.utf8.lexicographicallyPrecedes($1.url.fileSystemPath.utf8) }
    }

    /// The files of an app outside the home folder, below `root` ("/" on a
    /// Mac), in path order. They are never selected: they belong to root.
    public static func system(root: URL, target: Target, others: [String]) -> [AppFile] {
        let catalog = AppCatalog.shared
        if catalog.isProtected(target.bundleID) { return [] }
        let base = root.fileSystemPath == "/" ? "" : root.fileSystemPath
        var found: [String: AppFile] = [:]
        func add(_ path: String, _ fileClass: String, _ confidence: AppFile.Confidence) {
            guard let status = FileStatus(lstatPath: path), !status.isSymbolicLink,
                  !belongsToOther(URL(filePath: path).lastPathComponent, own: target.bundleID, others: others)
            else { return }
            if let old = found[path], old.confidence >= confidence { return }
            found[path] = AppFile(
                url: URL(filePath: path), fileClass: fileClass, confidence: confidence, isSelected: false,
                isDirectory: status.isDirectory, isSystem: true
            )
        }
        matchLocations(catalog.systemLocations, expand: { base + $0 }, target: target, add: add)
        for folder in catalog.launchdFolders where folder.hasPrefix("/") {
            let owned = launchdOwned(base + folder, target: target, root: base)
            for path in owned.lists + owned.helpers { add(path, "state", .high) }
        }
        return found.values.sorted { $0.url.fileSystemPath.utf8.lexicographicallyPrecedes($1.url.fileSystemPath.utf8) }
    }

    /// Expands each location for the target: a bundle ID match is high, a
    /// name or team match medium, a lower-case name low.
    static func matchLocations(
        _ locations: [AppCatalog.Location], expand: (String) -> String, target: Target,
        add: (String, String, AppFile.Confidence) -> Void
    ) {
        let generic = Set(AppCatalog.shared.genericNames)
        let name = target.name
        let nameOK = name.count >= 3 && !generic.contains(name.lowercased())
        for location in locations {
            let template = expand(location.path)
            if template.contains("{bundleID}") {
                guard isValidBundleID(target.bundleID) else { continue }
                for path in matchSegment(template, "{bundleID}", target.bundleID) { add(path, location.class, .high) }
            } else if template.contains("{name}") {
                guard nameOK else { continue }
                for path in matchSegment(template, "{name}", name) { add(path, location.class, .medium) }
            } else if template.contains("{lowername}") {
                let low = name.replacingOccurrences(of: " ", with: "").lowercased()
                guard nameOK, low.count >= 3, !generic.contains(low) else { continue }
                for path in matchSegment(template, "{lowername}", low) { add(path, location.class, .low) }
            } else if template.contains("{team}") {
                guard let team = target.team, team.wholeMatch(of: /[A-Z0-9]{10}/) != nil,
                      !target.otherTeams.contains(team)
                else { continue }
                for path in matchSegment(template, "{team}", team) { add(path, location.class, .medium) }
            }
        }
    }

    /// The property lists in `folder` that belong to the app: they name its
    /// bundle ID in AssociatedBundleIdentifiers, or their program is inside
    /// the bundle. `helpers` are the programs of those lists in
    /// /Library/PrivilegedHelperTools, below `root`.
    static func launchdOwned(_ folder: String, target: Target, root: String) -> (lists: [String], helpers: [String]) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return ([], []) }
        var lists: [String] = []
        var helpers: [String] = []
        for name in names.sorted() where name.hasSuffix(".plist") {
            let path = folder + "/" + name
            guard let status = FileStatus(lstatPath: path), !status.isDirectory, !status.isSymbolicLink,
                  let data = FileManager.default.contents(atPath: path),
                  let job = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }
            let program = job["Program"] as? String ?? (job["ProgramArguments"] as? [Any])?.first as? String ?? ""
            var owned = false
            if let bundle = target.bundle, bundle.hasSuffix(".app"), program.hasPrefix(bundle + "/") { owned = true }
            let associated = job["AssociatedBundleIdentifiers"].map { ($0 as? [Any])?.compactMap { $0 as? String } ?? [$0 as? String].compactMap { $0 } } ?? []
            if isValidBundleID(target.bundleID), associated.contains(where: { $0.caseInsensitiveCompare(target.bundleID) == .orderedSame }) {
                owned = true
            }
            guard owned else { continue }
            lists.append(path)
            let programURL = URL(filePath: program)
            if programURL.deletingLastPathComponent().path(percentEncoded: false).trimmingSuffix("/") == "/Library/PrivilegedHelperTools",
               !programURL.lastPathComponent.isEmpty {
                helpers.append(root + program)
            }
        }
        return (lists, helpers)
    }

    static func matchSegment(_ template: String, _ placeholder: String, _ value: String) -> [String] {
        let directory = (template as NSString).deletingLastPathComponent
        let segment = (template as NSString).lastPathComponent
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        let parts = segment.components(separatedBy: placeholder)
        let prefix = parts.first ?? ""
        let suffix = parts.count > 1 ? parts[1] : ""
        return names.filter { name in
            let lower = name.lowercased()
            if prefix.hasPrefix("*.") {
                let tail = ("." + value + suffix).lowercased()
                return lower.hasSuffix(tail) && name.count > value.count + suffix.count + 1
            }
            if suffix.hasPrefix(".*") {
                let rest = String(suffix.dropFirst(2)).lowercased()
                return lower.hasPrefix((prefix + value + ".").lowercased()) && lower.hasSuffix(rest)
            }
            return lower == (prefix + value + suffix).lowercased()
        }.map { directory + "/" + $0 }
    }

    static func belongsToOther(_ name: String, own: String, others: [String]) -> Bool {
        let lower = name.lowercased()
        return others.contains { other in
            let o = other.lowercased()
            guard o != own.lowercased(), o.count > own.count else { return false }
            return lower == o || lower.hasPrefix(o + ".") || lower.hasSuffix("." + o)
        }
    }

    static func fileClass(of path: String, home: URL) -> String {
        let library = home.appending(path: "Library").fileSystemPath + "/"
        let rel = path.hasPrefix(library) ? String(path.dropFirst(library.count)) : path
        if rel.hasPrefix("Caches/") || rel.hasPrefix("HTTPStorages/") || rel.hasPrefix("WebKit/") { return "cache" }
        if rel.hasPrefix("Logs/") { return "logs" }
        if rel.hasPrefix("Preferences/") { return "settings" }
        if rel.hasPrefix("Saved Application State/") || rel.hasPrefix("LaunchAgents/") { return "state" }
        return "data"
    }

    /// Data of an app that is no longer installed.
    public struct Leftover: Sendable, Hashable, Identifiable {
        public let url: URL
        public let bundleID: String
        public let fileClass: String
        public let isDirectory: Bool
        public var size: Int64 = 0
        public var id: String { url.fileSystemPath }

        public init(url: URL, bundleID: String, fileClass: String, isDirectory: Bool) {
            self.url = url
            self.bundleID = bundleID
            self.fileClass = fileClass
            self.isDirectory = isDirectory
        }
    }

    private static func vendor(_ id: String) -> String {
        let parts = id.lowercased().split(separator: ".", maxSplits: 2).map(String.init)
        return parts.count < 2 ? id.lowercased() : parts[0] + "." + parts[1]
    }


    /// Entries of the leftover roots whose name is a bundle ID that no
    /// installed app has; the same rules as the Go CLI. `installed` holds the
    /// known bundle IDs and `names` the names of the installed apps.
    /// `isInstalledElsewhere` asks LaunchServices about one ID. Nothing in the
    /// list is selected.
    public static func leftovers(
        home: URL, installed: [String], names: [String],
        isInstalledElsewhere: (String) -> Bool = { _ in false }
    ) -> [Leftover] {
        var vendors = Set<String>()
        var words = Set<String>()
        for id in installed {
            let v = vendor(id)
            vendors.insert(v)
            if let second = v.split(separator: ".").dropFirst().first, second.count >= 4 { words.insert(String(second)) }
        }
        for name in names {
            let word = name.replacingOccurrences(of: " ", with: "").lowercased()
            if word.count >= 4 { words.insert(word) }
        }
        let catalog = AppCatalog.shared
        func covered(_ id: String) -> Bool {
            if vendors.contains(vendor(id)) { return true }
            if id.lowercased().split(separator: ".").contains(where: { words.contains(String($0)) }) { return true }
            if catalog.leftoverIgnorePrefixes.contains(where: { id.lowercased().hasPrefix($0.lowercased()) }) { return true }
            return isInstalledElsewhere(id)
        }
        var out: [Leftover] = []
        for root in catalog.leftoverRoots {
            let directory = PathTemplate.expand(root, home: home).fileSystemPath
            let preferences = directory.hasSuffix("/Preferences")
            for name in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [] {
                let path = directory + "/" + name
                guard let status = FileStatus(lstatPath: path), !status.isSymbolicLink,
                      preferences == name.hasSuffix(".plist"), preferences != status.isDirectory
                else { continue }
                var id = name
                if id.hasSuffix(".plist") { id.removeLast(6) }
                if id.hasSuffix(".savedState") { id.removeLast(11) }
                guard id.filter({ $0 == "." }).count >= 2, isValidBundleID(id), !catalog.isProtected(id),
                      id.firstMatch(of: /(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/) == nil, !covered(id)
                else { continue }
                out.append(Leftover(url: URL(filePath: path), bundleID: id, fileClass: fileClass(of: path, home: home), isDirectory: status.isDirectory))
            }
        }
        return out.sorted { $0.url.fileSystemPath.utf8.lexicographicallyPrecedes($1.url.fileSystemPath.utf8) }
    }

    /// Asks LaunchServices whether an app with this bundle ID exists anywhere.
    public static let launchServicesKnows: @Sendable (String) -> Bool = { id in
        guard let urls = LSCopyApplicationURLsForBundleIdentifier(id as CFString, nil)?.takeRetainedValue() as? [URL] else {
            return false
        }
        return !urls.isEmpty
    }
}
