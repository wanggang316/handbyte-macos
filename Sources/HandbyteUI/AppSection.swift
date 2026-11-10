import Foundation

/// The sections of the app, in the order of the top bar.
public enum AppSection: String, Sendable, CaseIterable, Identifiable {
    case overview
    case clean
    case apps
    case storage
    case history

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .clean: "Clean"
        case .apps: "Apps"
        case .storage: "Storage"
        case .history: "History"
        }
    }

    /// False for a section that is planned but not built yet. The top bar
    /// shows it, and it opens a short description in place of a screen.
    public var isAvailable: Bool {
        switch self {
        case .overview, .clean, .storage, .history, .apps: true
        }
    }

    /// What a planned section will do. Empty for a section that is built.
    public var plannedSummary: String {
        switch self {
        case .overview, .clean, .storage, .history, .apps: ""
        }
    }
}
