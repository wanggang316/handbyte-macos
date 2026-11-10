import Foundation

/// The rule set, read from the shared catalog (`Resources/catalog`). The
/// catalog is a byte-identical copy of `catalog/` in the Go CLI repository,
/// in the same order: specific rules first, generic fallbacks last.
/// `scripts/sync-check.sh` fails CI when the two copies differ.
public enum Catalog {
    public static var rules: [Rule] { presets + projectArtifacts }

    /// Directories scanned for `projectArtifacts` unless the user configures others.
    public static var defaultProjectRoots: [String] { cleanup.projectRoots }

    /// Known locations below the home directory.
    public static var presets: [Rule] { cleanup.presets }

    /// The areas of a cleanup result, in order: ID and title.
    public static var areas: [(id: String, title: String)] { cleanup.areas }

    /// Directory names produced by build tools, matched under the project roots.
    public static var projectArtifacts: [Rule] { cleanup.projectArtifacts }

    private static let cleanup: CleanupCatalog = {
        guard let url = Bundle.module.url(forResource: "cleanup", withExtension: "json", subdirectory: "catalog") else {
            fatalError("catalog: cleanup.json is not in the resource bundle")
        }
        do {
            return try CleanupCatalog(data: Data(contentsOf: url))
        } catch {
            // A defective catalog is a build defect, not a runtime condition.
            fatalError("catalog: \(error)")
        }
    }()
}

/// The decoded content of `cleanup.json`.
struct CleanupCatalog: Sendable {
    let areas: [(id: String, title: String)]
    let projectRoots: [String]
    let presets: [Rule]
    let projectArtifacts: [Rule]

    struct Defect: Error, CustomStringConvertible {
        let description: String
    }

    private struct File: Decodable {
        struct Category: Decodable {
            let id: String
            let title: String
        }

        struct Entry: Decodable {
            let id: String
            let kind: String
            let path: String?
            let name: String?
            let expandChildren: Bool?
            let category: String
            let safety: String
            let owners: [String]?
            let summary: String
            let recovery: String
            let area: String
            let rebuildable: Bool
            let ownerName: String?
        }

        let version: Int
        let areas: [Category]
        let categories: [Category]
        let projectRoots: [String]
        let rules: [Entry]
    }

    init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.version == 2 else {
            throw Defect(description: "unsupported version \(file.version)")
        }
        let categories = Dictionary(Category.allCases.map { ($0.catalogID, $0) }, uniquingKeysWith: { first, _ in first })
        let tiers = Dictionary(Safety.allCases.map { ($0.catalogName, $0) }, uniquingKeysWith: { first, _ in first })
        for category in file.categories where categories[category.id]?.rawValue != category.title {
            throw Defect(description: "category \(category.id) is unknown or its title differs")
        }

        var presets: [Rule] = []
        var artifacts: [Rule] = []
        for entry in file.rules {
            guard let category = categories[entry.category], let safety = tiers[entry.safety] else {
                throw Defect(description: "rule \(entry.id): unknown category or safety")
            }
            let kind: Rule.Kind
            switch (entry.kind, entry.path, entry.name) {
            case ("preset", let path?, nil) where path.hasPrefix("~/")
                && path.split(separator: "/").allSatisfy({ !$0.contains("*") || $0 == "*" }):
                kind = .preset(pathTemplate: path, expandChildren: entry.expandChildren ?? false)
            case ("artifact", nil, let name?) where entry.id == "artifact:\(name)":
                kind = .projectArtifact(directoryName: name)
            default:
                throw Defect(description: "rule \(entry.id): kind, path and name do not agree")
            }
            let rule = Rule(
                id: entry.id,
                kind: kind,
                category: category,
                safety: safety,
                ownerBundleIDs: entry.owners ?? [],
                summary: entry.summary,
                recovery: entry.recovery,
                area: entry.area,
                rebuildable: entry.rebuildable,
                ownerName: entry.ownerName
            )
            guard file.areas.contains(where: { $0.id == entry.area }) else {
                throw Defect(description: "rule \(entry.id): unknown area \(entry.area)")
            }
            if rule.directoryName == nil {
                presets.append(rule)
            } else {
                artifacts.append(rule)
            }
        }
        self.areas = file.areas.map { ($0.id, $0.title) }
        self.projectRoots = file.projectRoots
        self.presets = presets
        self.projectArtifacts = artifacts
    }
}
