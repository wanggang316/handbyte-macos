import Foundation
import HandbyteCore

/// Finds the cleanup rule that covers a folder of the storage view, so that
/// the view can point to Clean. A hint is not a verdict: Clean scans the
/// folder again and applies its own checks before any action.
public struct CleanupHints: Sendable {
    /// Exact locations of presets, and the folders whose children a preset
    /// expands to. The more specific rule is kept when two reach one path.
    private let exact: [String: Rule]
    private let parents: [String: Rule]
    private let artifacts: [String: Rule]
    private let roots: [String]

    public init(rules: [Rule], home: URL, projectRoots: [String]) {
        var exact: [String: Rule] = [:]
        var parents: [String: Rule] = [:]
        var artifacts: [String: Rule] = [:]
        func keep(_ rule: Rule, in table: inout [String: Rule], at path: String) {
            if let other = table[path], !rule.isMoreSpecific(than: other) { return }
            table[path] = rule
        }
        for rule in rules {
            if let name = rule.directoryName {
                artifacts[name] = artifacts[name] ?? rule
            } else if let location = rule.location(in: home)?.path(percentEncoded: false) {
                let path = Self.normal(location)
                if rule.expandChildren {
                    keep(rule, in: &parents, at: path)
                } else {
                    keep(rule, in: &exact, at: path)
                }
            }
        }
        self.exact = exact
        self.parents = parents
        self.artifacts = artifacts
        roots = projectRoots.map { Self.normal(PathTemplate.expand($0, home: home).path(percentEncoded: false)) }
    }

    public func rule(for path: String) -> Rule? {
        let path = Self.normal(path)
        let parent = Self.normal((path as NSString).deletingLastPathComponent)
        switch (exact[path], parents[parent]) {
        case let (preset?, expanded?):
            return expanded.isMoreSpecific(than: preset) ? expanded : preset
        case let (preset?, nil):
            return preset
        case let (nil, expanded?):
            return expanded
        case (nil, nil):
            break
        }
        let name = (path as NSString).lastPathComponent
        if let rule = artifacts[name], roots.contains(where: { path.hasPrefix($0 + "/") && path != $0 }) {
            return rule
        }
        return nil
    }

    private static func normal(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
