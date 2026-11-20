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

    @Test func focusedListShowsItsFrameOnlyWithoutAVisibleHighlightedRow() {
        #expect(ListFocus.showsFrame(hasFocus: true, selection: nil as Int?, ids: [1, 2]))
        #expect(!ListFocus.showsFrame(hasFocus: true, selection: 1, ids: [1, 2]))
        #expect(!ListFocus.showsFrame(hasFocus: false, selection: nil as Int?, ids: [1, 2]))
    }

    @Test func aSelectionThatTheListDoesNotShowCountsAsNone() {
        // A filter can hide the selected row; the list must still show focus.
        #expect(ListFocus.showsFrame(hasFocus: true, selection: 3, ids: [1, 2]))
    }
}
