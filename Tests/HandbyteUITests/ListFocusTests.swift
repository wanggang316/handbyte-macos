import CoreGraphics
import Testing
@testable import HandbyteUI

@Suite("List focus")
struct ListFocusTests {
    @Test func highlightedRowIsStrongerWhileItsListHasFocus() {
        #expect(RowEmphasis(isHighlighted: true, isHovered: false, listHasFocus: true) == .focusedHighlight)
        #expect(RowEmphasis(isHighlighted: true, isHovered: false, listHasFocus: false) == .highlight)
    }

    @Test func highlightWinsOverHover() {
        #expect(RowEmphasis(isHighlighted: true, isHovered: true, listHasFocus: false) == .highlight)
        #expect(RowEmphasis(isHighlighted: true, isHovered: true, listHasFocus: true) == .focusedHighlight)
    }

    @Test func otherRowsShowOnlyHover() {
        #expect(RowEmphasis(isHighlighted: false, isHovered: true, listHasFocus: true) == .hover)
        #expect(RowEmphasis(isHighlighted: false, isHovered: false, listHasFocus: true) == .none)
    }

    let viewport = CGRect(x: 0, y: 0, width: 400, height: 300)

    @Test func focusedListShowsItsFrameOnlyWithoutAVisibleHighlightedRow() {
        let row = CGRect(x: 10, y: 100, width: 380, height: 44)
        #expect(!ListFocus.showsFrame(hasFocus: true, highlightedRow: row, viewport: viewport))
        #expect(ListFocus.showsFrame(hasFocus: true, highlightedRow: nil, viewport: viewport))
        #expect(!ListFocus.showsFrame(hasFocus: false, highlightedRow: nil, viewport: viewport))
    }

    @Test func aHighlightedRowScrolledOutOfTheViewportCountsAsNone() {
        // Scrolling with the pointer does not move the highlight.
        let above = CGRect(x: 10, y: -200, width: 380, height: 44)
        let below = CGRect(x: 10, y: 320, width: 380, height: 44)
        #expect(ListFocus.showsFrame(hasFocus: true, highlightedRow: above, viewport: viewport))
        #expect(ListFocus.showsFrame(hasFocus: true, highlightedRow: below, viewport: viewport))
    }

    @Test func aRowMostlyOutOfTheViewportCountsAsNone() {
        let sliver = CGRect(x: 10, y: 290, width: 380, height: 44)
        let mostly = CGRect(x: 10, y: 270, width: 380, height: 44)
        #expect(ListFocus.showsFrame(hasFocus: true, highlightedRow: sliver, viewport: viewport))
        #expect(!ListFocus.showsFrame(hasFocus: true, highlightedRow: mostly, viewport: viewport))
    }
}
