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
}
