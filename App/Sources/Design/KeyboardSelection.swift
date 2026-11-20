import SwiftUI

extension View {
    /// Lets a scroll view of rows take the keyboard focus. The up and down
    /// arrows move the selection, Return or the right arrow opens the
    /// selected row, the left arrow goes back. The list scrolls to each new
    /// selection, also one that `open` or `back` set. Rows that are not a `List`
    /// get no keyboard path from SwiftUI, so the lists of the app use this.
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

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .focusable()
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
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

    private func move(_ step: Int) -> KeyPress.Result {
        guard !ids.isEmpty else { return .ignored }
        let index = selection.flatMap { ids.firstIndex(of: $0) }
        let next = index.map { min(max($0 + step, 0), ids.count - 1) } ?? (step > 0 ? 0 : ids.count - 1)
        selection = ids[next]
        return .handled
    }

    private func openSelection() -> KeyPress.Result {
        guard let open, let selection else { return .ignored }
        open(selection)
        return .handled
    }
}
