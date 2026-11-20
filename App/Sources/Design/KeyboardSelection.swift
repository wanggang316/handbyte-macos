import HandbyteUI
import SwiftUI

extension View {
    /// Lets a scroll view of rows take the keyboard focus. The up and down
    /// arrows move the selection, Return or the right arrow opens the
    /// selected row, the left arrow goes back. The list scrolls to each new
    /// selection, also one that `open` or `back` set. Rows that are not a `List`
    /// get no keyboard path from SwiftUI, so the lists of the app use this.
    ///
    /// Rows read `listHasFocus` through `hbRowBackground`. A focused list
    /// with no highlighted row on screen shows a quiet frame.
    func keyboardSelection<ID: Hashable>(
        _ ids: [ID],
        selection: Binding<ID?>,
        open: ((ID) -> Void)? = nil,
        back: (() -> Void)? = nil
    ) -> some View {
        modifier(KeyboardSelection(ids: ids, selection: selection, open: open, back: back))
    }
}

private struct KeyboardSelection<ID: Hashable>: ViewModifier {
    let ids: [ID]
    @Binding var selection: ID?
    let open: ((ID) -> Void)?
    let back: (() -> Void)?
    @FocusState private var hasFocus: Bool

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .environment(\.listHasFocus, hasFocus)
                .overlay {
                    if ListFocus.showsFrame(hasFocus: hasFocus, selection: selection, ids: ids) {
                        RoundedRectangle(cornerRadius: HB.Radius.medium, style: .continuous)
                            .strokeBorder(HB.Palette.borderStrong, lineWidth: 1)
                            .padding(2)
                            .allowsHitTesting(false)
                    }
                }
                .focusable()
                .focused($hasFocus)
                // The system ring uses the accent color and frames the whole
                // list; the rows and the frame above show the focus. This
                // also removes the ring of each control in the rows, and the
                // control cannot turn it on again; such a control uses
                // `hbFocusRing()`.
                .focusEffectDisabled()
                .onKeyPress(.downArrow) { move(1, proxy) }
                .onKeyPress(.upArrow) { move(-1, proxy) }
                .onKeyPress(.return) { openSelection() }
                .onKeyPress(.rightArrow) { openSelection() }
                .onKeyPress(.leftArrow) {
                    guard let back else { return .ignored }
                    back()
                    return .handled
                }
                // In a key handler the binding still reads the old value, so
                // the scroll waits for the change.
                .onChange(of: selection) { _, selection in
                    if let selection { proxy.scrollTo(selection) }
                }
        }
    }

    private func move(_ step: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !ids.isEmpty else { return .ignored }
        let index = selection.flatMap { ids.firstIndex(of: $0) }
        let next = index.map { min(max($0 + step, 0), ids.count - 1) } ?? (step > 0 ? 0 : ids.count - 1)
        if ids[next] == selection {
            // At the first or last row the selection does not change, so
            // onChange does not run; bring the row back if it was scrolled away.
            proxy.scrollTo(ids[next])
        } else {
            selection = ids[next]
        }
        return .handled
    }

    private func openSelection() -> KeyPress.Result {
        guard let open, let selection else { return .ignored }
        open(selection)
        return .handled
    }
}

extension EnvironmentValues {
    /// Whether the keyboard list around this view has the focus.
    @Entry var listHasFocus = false
}

private struct RowBackground: ViewModifier {
    let isHighlighted: Bool
    let isHovered: Bool
    @Environment(\.listHasFocus) private var listHasFocus

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: HB.Radius.small, style: .continuous)
        content
            .background(fill, in: shape)
            // The same line as the frame of a focused list without a
            // highlighted row: it marks where the keys go.
            .overlay {
                if emphasis == .focusedHighlight {
                    shape.strokeBorder(HB.Palette.borderStrong, lineWidth: 1).allowsHitTesting(false)
                }
            }
    }

    private var emphasis: RowEmphasis {
        RowEmphasis(isHighlighted: isHighlighted, isHovered: isHovered, listHasFocus: listHasFocus)
    }

    private var fill: Color {
        switch emphasis {
        case .focusedHighlight: HB.Palette.activeFocused
        case .highlight: HB.Palette.active
        case .hover: HB.Palette.hover
        case .none: .clear
        }
    }
}

extension View {
    /// The fill of a row in a keyboard list: the highlighted row is stronger
    /// and outlined while its list has the focus.
    func hbRowBackground(isHighlighted: Bool, hovering: Bool) -> some View {
        modifier(RowBackground(isHighlighted: isHighlighted, isHovered: hovering))
    }
}

private struct FocusRing: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(HB.Palette.text, lineWidth: 2)
                        .padding(-3)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /// The focus ring of a control in a row of a keyboard list, where the
    /// system ring is off. Full Keyboard Access moves the focus to it.
    func hbFocusRing() -> some View {
        modifier(FocusRing())
    }
}
