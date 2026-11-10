import Foundation
import HandbyteCore

/// What Smart Clean takes and how its result reads, area by area. The input
/// is the labelled result of a scan.
public struct SmartCleanPlan: Sendable, Equatable {
    public struct Area: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public var safeBytes: Int64 = 0
        public var safeCount = 0
        public var reviewBytes: Int64 = 0
        public var skippedBytes: Int64 = 0
        /// The reason of the largest skipped item, for the area line.
        public var skippedReason: String?
    }

    /// The safe items, without one inside another. Never an item of the
    /// review tier.
    public let selection: [Candidate]
    /// Areas with at least one item, in catalog order.
    public let areas: [Area]

    public var safeBytes: Int64 { areas.reduce(0) { $0 + $1.safeBytes } }
    public var reviewBytes: Int64 { areas.reduce(0) { $0 + $1.reviewBytes } }
    public var skippedBytes: Int64 { areas.reduce(0) { $0 + $1.skippedBytes } }

    public init(candidates: [Candidate]) {
        var picker = Selection(candidates: candidates)
        picker.selectAllSafe()
        let chosen = picker.selectedIDs
        selection = candidates.filter { chosen.contains($0.id) }

        var areas = Catalog.areas.map { Area(id: $0.id, title: $0.title) }
        var largestSkipped: [String: Int64] = [:]
        for candidate in candidates {
            guard let index = areas.firstIndex(where: { $0.id == candidate.rule.area }) else { continue }
            let bytes = candidate.size.allocatedBytes
            // An item inside a chosen item goes with it and counts once.
            if !chosen.contains(candidate.id),
               selection.contains(where: { PathRelation.isAncestor($0.url, of: candidate.url) }) {
                continue
            }
            if chosen.contains(candidate.id) {
                areas[index].safeBytes += bytes
                areas[index].safeCount += 1
            } else if picker.canSelect(candidate) {
                areas[index].reviewBytes += bytes
            } else {
                areas[index].skippedBytes += bytes
                if bytes >= largestSkipped[candidate.rule.area, default: -1] {
                    largestSkipped[candidate.rule.area] = bytes
                    areas[index].skippedReason = candidate.eligibility.blockedReason
                }
            }
        }
        self.areas = areas.filter { $0.safeBytes + $0.reviewBytes + $0.skippedBytes > 0 }
    }
}

extension Eligibility {
    public var blockedReason: String? {
        if case .blocked(let reason) = self { return reason }
        return nil
    }

    public var reviewOnlyReason: String? {
        if case .reviewOnly(let reason) = self { return reason }
        return nil
    }
}
