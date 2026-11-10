import Foundation
import HandbyteCore

/// Splits the used space of the volume for the meter of the Overview: the
/// categories of the home folder from the last storage scan, and the rest of
/// the disk. The same rule as the home screen of the CLI.
public enum VolumeBreakdown {
    public struct Part: Sendable, Hashable, Identifiable {
        public let id: String
        public let title: String
        public let bytes: Int64

        public init(id: String, title: String, bytes: Int64) {
            self.id = id
            self.title = title
            self.bytes = bytes
        }
    }

    public static func parts(volume: VolumeUsage, home: UsageSummary?) -> [Part] {
        guard let home else {
            return [Part(id: StorageCatalog.other, title: "Used", bytes: volume.usedBytes)]
        }
        // Other in the home folder and all outside it share one grey part,
        // so that the meter has few colors.
        var parts = home.categories
            .filter { $0.id != StorageCatalog.other && $0.allocatedBytes > 0 }
            .map { Part(id: $0.id, title: StorageCatalog.shared.title(of: $0.id), bytes: $0.allocatedBytes) }
        let rest = volume.usedBytes - parts.reduce(0) { $0 + $1.bytes }
        if rest > 0 {
            parts.append(Part(id: StorageCatalog.other, title: "System and other", bytes: rest))
        }
        return parts
    }
}
