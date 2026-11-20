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
    /// no row can show the focus. A selection that a filter hid counts as none.
    public static func showsFrame<ID: Equatable>(hasFocus: Bool, selection: ID?, ids: [ID]) -> Bool {
        guard hasFocus else { return false }
        guard let selection else { return true }
        return !ids.contains(selection)
    }
}
