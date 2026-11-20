import Foundation
import HandbyteCore

/// One line of the review list that the keyboard can highlight.
public enum ReviewListItem: Hashable, Sendable {
    case group(HandbyteCore.Category)
    case candidate(Candidate.ID)
}

/// Which groups of the review list are collapsed, and which line is
/// highlighted. The highlight is always a line on screen: when the search or
/// a collapse hides it, it clears, so the detail pane and Space never act on
/// a line the user cannot see.
///
/// The arrows work like an outline: up and down move over the group headers
/// and the rows; left moves from a row to its header, then collapses the
/// group; right expands a group, then moves to its first row.
public struct ReviewOutline: Sendable, Equatable {
    public var collapsed: Set<HandbyteCore.Category> = []
    public var highlighted: ReviewListItem?

    public init() {}

    public func isExpanded(_ category: HandbyteCore.Category) -> Bool {
        !collapsed.contains(category)
    }

    public var highlightedCandidateID: Candidate.ID? {
        if case .candidate(let id) = highlighted { return id }
        return nil
    }

    /// The lines on screen from top to bottom, for keyboard movement.
    public func items(in list: ReviewList) -> [ReviewListItem] {
        list.groups.flatMap { group in
            [.group(group.category)] + (isExpanded(group.category) ? group.candidates.map { .candidate($0.id) } : [])
        }
    }

    public mutating func toggleExpansion(_ category: HandbyteCore.Category, in list: ReviewList) {
        if collapsed.contains(category) {
            collapsed.remove(category)
        } else {
            collapsed.insert(category)
        }
        dropHiddenHighlight(in: list)
    }

    /// Call after the list changes, for example after a new search query.
    public mutating func dropHiddenHighlight(in list: ReviewList) {
        if let highlighted, !items(in: list).contains(highlighted) {
            self.highlighted = nil
        }
    }

    /// The left arrow.
    public mutating func moveOut(in list: ReviewList) {
        switch highlighted {
        case .candidate(let id):
            guard let group = list.groups.first(where: { $0.candidates.contains { $0.id == id } }) else { return }
            highlighted = .group(group.category)
        case .group(let category):
            if isExpanded(category) { toggleExpansion(category, in: list) }
        case nil:
            break
        }
    }

    /// The right arrow.
    public mutating func moveIn(in list: ReviewList) {
        guard case .group(let category) = highlighted else { return }
        if !isExpanded(category) {
            toggleExpansion(category, in: list)
        } else if let first = list.groups.first(where: { $0.category == category })?.candidates.first {
            highlighted = .candidate(first.id)
        }
    }
}
