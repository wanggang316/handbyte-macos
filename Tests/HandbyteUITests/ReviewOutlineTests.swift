import Foundation
import Testing
import HandbyteCore
@testable import HandbyteUI

@Suite("Review outline")
struct ReviewOutlineTests {
    let xcode = Fixtures.candidate(
        path: "/Users/alice/Library/Developer/Xcode/DerivedData",
        rule: Fixtures.rule(id: "xcode-derived", category: .xcode), bytes: 900
    )
    let brew = Fixtures.candidate(
        path: "/Users/alice/Library/Caches/Homebrew",
        rule: Fixtures.rule(id: "brew-cache", category: .devCache), bytes: 300
    )
    let go = Fixtures.candidate(
        path: "/Users/alice/Library/Caches/go-build",
        rule: Fixtures.rule(id: "go-build", category: .devCache), bytes: 500
    )

    var list: ReviewList { ReviewList(candidates: [brew, xcode, go]) }

    @Test func itemsListEachHeaderThenTheRowsOfExpandedGroups() {
        var outline = ReviewOutline()
        #expect(outline.items(in: list) == [.group(.devCache), .candidate(go.id), .candidate(brew.id),
                                            .group(.xcode), .candidate(xcode.id)])
        outline.toggleExpansion(.devCache, in: list)
        #expect(!outline.isExpanded(.devCache))
        #expect(outline.items(in: list) == [.group(.devCache), .group(.xcode), .candidate(xcode.id)])
    }

    @Test func collapsingTheGroupOfTheHighlightedRowClearsTheHighlight() {
        var outline = ReviewOutline()
        outline.highlighted = .candidate(brew.id)
        outline.toggleExpansion(.xcode, in: list)
        #expect(outline.highlightedCandidateID == brew.id)
        outline.toggleExpansion(.devCache, in: list)
        #expect(outline.highlighted == nil)
        #expect(outline.highlightedCandidateID == nil)
    }

    @Test func searchThatHidesTheHighlightedRowClearsTheHighlight() {
        var outline = ReviewOutline()
        var list = list
        outline.highlighted = .candidate(brew.id)
        list.query = "brew"
        outline.dropHiddenHighlight(in: list)
        #expect(outline.highlighted == .candidate(brew.id))
        list.query = "xcode"
        outline.dropHiddenHighlight(in: list)
        #expect(outline.highlighted == nil)
    }

    @Test func searchThatHidesAHighlightedGroupClearsTheHighlight() {
        var outline = ReviewOutline()
        var list = list
        outline.highlighted = .group(.devCache)
        list.query = "xcode"
        outline.dropHiddenHighlight(in: list)
        #expect(outline.highlighted == nil)
    }

    @Test func leftArrowMovesFromARowToItsHeaderThenCollapses() {
        var outline = ReviewOutline()
        outline.highlighted = .candidate(brew.id)
        outline.moveOut(in: list)
        #expect(outline.highlighted == .group(.devCache))
        #expect(outline.isExpanded(.devCache))
        outline.moveOut(in: list)
        #expect(!outline.isExpanded(.devCache))
        #expect(outline.highlighted == .group(.devCache))
        outline.moveOut(in: list)
        #expect(!outline.isExpanded(.devCache))
        #expect(outline.highlighted == .group(.devCache))
    }

    @Test func rightArrowExpandsAHeaderThenMovesToItsFirstRow() {
        var outline = ReviewOutline()
        outline.toggleExpansion(.devCache, in: list)
        outline.highlighted = .group(.devCache)
        outline.moveIn(in: list)
        #expect(outline.isExpanded(.devCache))
        #expect(outline.highlighted == .group(.devCache))
        outline.moveIn(in: list)
        #expect(outline.highlighted == .candidate(go.id))
        outline.moveIn(in: list)
        #expect(outline.highlighted == .candidate(go.id))
    }

    @Test func arrowsWithoutAHighlightDoNothing() {
        var outline = ReviewOutline()
        outline.moveIn(in: list)
        outline.moveOut(in: list)
        #expect(outline == ReviewOutline())
    }
}
