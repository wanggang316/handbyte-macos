import Foundation
import HandbyteCore

/// Finds the cleanup rule that covers a folder of the storage view, so that
/// the view can point to Clean. A hint is not a verdict: Clean scans the
/// folder again and applies its own checks before any action. The same rule
/// as `scanner.Hints` of the Go CLI.
public struct CleanupHints: Sendable {
    private let presets: [(rule: Rule, template: [String])]
    private let artifacts: [String: Rule]
    private let roots: [String]

    public init(rules: [Rule], home: URL, projectRoots: [String]) {
        var presets: [(Rule, [String])] = []
        var artifacts: [String: Rule] = [:]
        // A rule of the caution tier gives no hint: it holds user data, and
        // the view must not call it cleanable.
        for rule in rules where rule.safety != .caution {
            if let name = rule.directoryName {
                artifacts[name] = artifacts[name] ?? rule
            } else if let location = rule.location(in: home) {
                presets.append((rule, Self.segments(location.fileSystemPath)))
            }
        }
        self.presets = presets
        self.artifacts = artifacts
        roots = projectRoots.map { PathTemplate.expand($0, home: home).fileSystemPath }
    }

    public func rule(for path: String) -> Rule? {
        let parts = Self.segments(path)
        var best: Rule?
        var bestDepth = -1
        for (rule, template) in presets {
            let target = rule.expandChildren ? Array(parts.dropLast()) : parts
            let depth = template.count + (rule.expandChildren ? 1 : 0)
            if Self.matches(template, target), depth > bestDepth {
                best = rule
                bestDepth = depth
            }
        }
        if let best {
            // A folder that holds the location of another rule is not
            // covered, as in a cleanup scan.
            let holdsAnother = presets.contains { _, template in
                template.count > parts.count && Self.matches(Array(template.prefix(parts.count)), parts)
            }
            return holdsAnother ? nil : best
        }
        if let rule = artifacts[parts.last ?? ""],
           roots.contains(where: { UsageCategories.isBelow(path, $0) }) {
            return rule
        }
        return nil
    }

    private static func segments(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }

    private static func matches(_ template: [String], _ path: [String]) -> Bool {
        guard template.count == path.count else { return false }
        return zip(template, path).allSatisfy { t, p in
            t == "*" ? !p.hasPrefix(".") && !p.isEmpty : t == p
        }
    }
}
