import Foundation
import HandbyteCore

/// Capacity of the volume that holds the home folder.
public struct VolumeUsage: Sendable, Equatable {
    public let totalBytes: Int64
    /// Space for new files, including the purgeable space.
    public let availableBytes: Int64
    /// Space that is free now, without the purgeable space. Nil when unknown.
    public let immediatelyAvailableBytes: Int64?

    public init(totalBytes: Int64, availableBytes: Int64, immediatelyAvailableBytes: Int64? = nil) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.immediatelyAvailableBytes = immediatelyAvailableBytes
    }

    /// Space that macOS frees by itself when it needs it: local snapshots,
    /// caches of iCloud files and similar. Zero when unknown.
    public var purgeableBytes: Int64 {
        guard let immediate = immediatelyAvailableBytes else { return 0 }
        return max(0, availableBytes - immediate)
    }

    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }

    /// Between 0 and 1; 0 when the capacity is unknown.
    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
}

/// What the Overview shows: one number, its label and the main action.
public struct OverviewSummary: Sendable, Equatable {
    public enum PrimaryAction: Sendable, Equatable {
        /// Start a scan.
        case scan
        /// Open the result of the last scan.
        case review
    }

    /// The large number. Nil when there is nothing to show.
    public let heroBytes: Int64?
    public let heroLabel: String
    public let detail: String
    public let primaryAction: PrimaryAction
    /// Items a bulk pick would take: eligible and safe.
    public let safeCount: Int
    /// Bytes of the selectable items that need a review first.
    public let reviewBytes: Int64

    /// `candidates` is the labelled result of the last scan in this session,
    /// or nil when no scan ran yet.
    public init(candidates: [Candidate]?, volume: VolumeUsage?) {
        guard let candidates else {
            heroBytes = volume?.availableBytes
            heroLabel = "free"
            detail = "Not scanned yet"
            primaryAction = .scan
            safeCount = 0
            reviewBytes = 0
            return
        }
        // The same rule as "Select all safe", so the number is what one
        // click selects, with nested items counted once.
        var selection = Selection(candidates: candidates)
        selection.selectAllSafe()
        let safeBytes = selection.selectedBytes
        safeCount = selection.selectedIDs.count
        reviewBytes = candidates
            .filter { selection.canSelect($0) && !selection.isSelected($0.id) }
            .reduce(0) { $0 + $1.size.allocatedBytes }
        heroBytes = safeBytes
        heroLabel = "safe to clean"
        if safeCount == 0 {
            detail = "Nothing safe to clean was found"
            primaryAction = .scan
        } else {
            detail = safeCount == 1 ? "1 item" : "\(safeCount) items"
            primaryAction = .review
        }
    }
}
