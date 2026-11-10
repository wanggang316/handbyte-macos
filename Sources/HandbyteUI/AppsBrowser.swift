import Foundation
import HandbyteCore

/// The state of the Apps section that is not tied to the view: the filter,
/// the search and the rows of the list.
public struct AppsBrowser: Sendable, Equatable {
    public enum Filter: String, Sendable, CaseIterable, Identifiable {
        case all = "All"
        case unused = "Unused"
        case largest = "Largest"
        case leftovers = "Leftovers"
        public var id: String { rawValue }
    }

    public var filter: Filter = .all
    public var query = ""
    public private(set) var apps: [InstalledApp]

    public init(apps: [InstalledApp]) {
        self.apps = apps
    }

    public mutating func setSize(_ size: Int64, for id: InstalledApp.ID) {
        if let index = apps.firstIndex(where: { $0.id == id }) { apps[index].size = size }
    }

    /// The apps of the filter and the search, in the order of the filter.
    public func rows(now: Date) -> [InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var rows = apps.filter { app in
            q.isEmpty || app.name.lowercased().contains(q) || app.bundleID.lowercased().contains(q)
        }
        switch filter {
        case .all, .leftovers:
            break
        case .unused:
            rows = rows.filter { $0.isUnused(now: now) }.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        case .largest:
            rows.sort { $0.size > $1.size }
        }
        return rows
    }

    public var totalSize: Int64 { apps.reduce(0) { $0 + $1.size } }
}

/// The data of one removed app, from all roots.
public struct LeftoverGroup: Sendable, Equatable, Identifiable {
    public let bundleID: String
    public var items: [AppFiles.Leftover]
    public var size: Int64 { items.reduce(0) { $0 + $1.size } }
    public var id: String { bundleID }

    /// Groups by the first three parts of the bundle ID, so that the data of
    /// helpers and tests is one group. Largest first.
    public static func group(_ items: [AppFiles.Leftover]) -> [LeftoverGroup] {
        var order: [String] = []
        var groups: [String: LeftoverGroup] = [:]
        for item in items {
            let parts = item.bundleID.split(separator: ".", maxSplits: 3)
            let key = parts.count > 3 ? parts.prefix(3).joined(separator: ".") : item.bundleID
            if groups[key] == nil {
                order.append(key)
                groups[key] = LeftoverGroup(bundleID: key, items: [])
            }
            groups[key]?.items.append(item)
        }
        return order.compactMap { groups[$0] }.enumerated()
            .sorted { $0.element.size != $1.element.size ? $0.element.size > $1.element.size : $0.offset < $1.offset }
            .map(\.element)
    }
}
