import CoreGraphics

/// How a row of a keyboard list is emphasized. The highlighted row is
/// stronger while its list has the keyboard focus, so the user can see where
/// the keys go after another control takes the focus.
public enum RowEmphasis: Sendable, Equatable {
    case none
    case hover
    case highlight
    case focusedHighlight

    public init(isHighlighted: Bool, isHovered: Bool, listHasFocus: Bool) {
        if isHighlighted {
            self = listHasFocus ? .focusedHighlight : .highlight
        } else {
            self = isHovered ? .hover : .none
        }
    }
}

public enum ListFocus {
    /// A focused list without a highlighted row on screen shows a frame, as
    /// no row can show the focus. `highlightedRow` is the frame of the
    /// highlighted row in the coordinates of the list, or nil when no row is
    /// highlighted or drawn (a filter hid it, or it scrolled far away). A row
    /// that is less than half in the viewport counts as not on screen.
    public static func showsFrame(hasFocus: Bool, highlightedRow: CGRect?, viewport: CGRect) -> Bool {
        guard hasFocus else { return false }
        guard let row = highlightedRow, row.height > 0 else { return true }
        let visible = row.intersection(viewport)
        return visible.isNull || visible.height < row.height / 2
    }
}
