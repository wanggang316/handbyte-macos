import Foundation

/// The commands of the palette (⌘K) and how a query picks them.
public struct PaletteCommand: Sendable, Equatable, Identifiable {
    public enum Action: Sendable, Equatable {
        case show(AppSection)
        case smartClean
        case chooseItems
        case scanStorage
        case leftovers
        case settings
        case operationsLog
    }

    public let title: String
    /// Other words that find the command.
    public let keywords: [String]
    public let action: Action
    public var id: String { title }

    public static let all: [PaletteCommand] = [
        PaletteCommand(title: "Clean now", keywords: ["smart", "cache", "free space"], action: .smartClean),
        PaletteCommand(title: "Choose items to clean", keywords: ["review", "list", "select"], action: .chooseItems),
        PaletteCommand(title: "Scan storage", keywords: ["disk", "folders", "treemap", "largest"], action: .scanStorage),
        PaletteCommand(title: "Uninstall an app", keywords: ["apps", "remove", "delete"], action: .show(.apps)),
        PaletteCommand(title: "Leftovers of removed apps", keywords: ["apps", "orphan", "remains"], action: .leftovers),
        PaletteCommand(title: "Go to Overview", keywords: ["home", "start"], action: .show(.overview)),
        PaletteCommand(title: "Go to Clean", keywords: [], action: .show(.clean)),
        PaletteCommand(title: "Go to Apps", keywords: [], action: .show(.apps)),
        PaletteCommand(title: "Go to Storage", keywords: ["disk"], action: .show(.storage)),
        PaletteCommand(title: "Go to History", keywords: ["restore", "undo", "log"], action: .show(.history)),
        PaletteCommand(title: "Settings", keywords: ["preferences", "trash", "roots", "exclusions"], action: .settings),
        PaletteCommand(title: "Show operations log in Finder", keywords: ["journal", "audit"], action: .operationsLog),
    ]

    /// The commands that match every word of the query, best first: a match
    /// at the start of the title before a match inside it, then by order.
    public static func matching(_ query: String, in commands: [PaletteCommand] = all) -> [PaletteCommand] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return commands }
        let scored = commands.enumerated().compactMap { index, command -> (Int, Int, PaletteCommand)? in
            let title = command.title.lowercased()
            let haystack = ([title] + command.keywords).joined(separator: " ")
            guard words.allSatisfy({ haystack.contains($0) }) else { return nil }
            let starts = title.hasPrefix(words[0]) || title.split(separator: " ").contains { $0.hasPrefix(words[0]) }
            return (starts ? 0 : 1, index, command)
        }
        return scored.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)
    }
}
