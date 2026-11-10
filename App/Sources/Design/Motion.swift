import SwiftUI

/// Animation helpers that follow Reduce Motion. With Reduce Motion on, a
/// change shows at once and a view that comes or goes only fades.
extension View {
    /// `animation(_:value:)`, but no animation with Reduce Motion.
    func hbAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ReducibleAnimation(animation: animation, value: value))
    }

    /// `transition(_:)`, but a plain fade with Reduce Motion.
    func hbTransition(_ transition: AnyTransition) -> some View {
        modifier(ReducibleTransition(transition: transition))
    }

    /// Rolls the digits of a changing number, or fades it with Reduce Motion.
    func hbNumericTransition() -> some View {
        modifier(ReducibleNumericTransition())
    }
}

private struct ReducibleAnimation<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct ReducibleTransition: ViewModifier {
    let transition: AnyTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : transition)
    }
}

private struct ReducibleNumericTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.contentTransition(reduceMotion ? .opacity : .numericText())
    }
}
