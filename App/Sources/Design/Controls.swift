import SwiftUI

/// The one large action of a screen: an ink pill. It lifts and gains a ring
/// under the pointer, and goes down when pressed.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration)
    }

    private struct PillBody: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let active = hovering && isEnabled
            configuration.label
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HB.Palette.onInk)
                .padding(.horizontal, 28)
                .frame(height: 48)
                .background(active ? HB.Palette.inkHover : HB.Palette.ink, in: Capsule())
                .background(Capsule().fill(HB.Palette.active).padding(active ? -4 : 0))
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .offset(y: reduceMotion ? 0 : (configuration.isPressed ? 1 : (active ? -1 : 0)))
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(HB.Motion.quick, value: active)
                .animation(HB.Motion.quick, value: configuration.isPressed)
        }
    }
}

/// A text link: secondary text with a faint underline that turns to full
/// contrast under the pointer.
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LinkBody(configuration: configuration)
    }

    private struct LinkBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(HB.Typography.body)
                .foregroundStyle(hovering ? HB.Palette.text : HB.Palette.textSecondary)
                .underline(color: hovering ? HB.Palette.text : HB.Palette.borderStrong)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(HB.Motion.quick, value: hovering)
        }
    }
}

/// A tab of the top bar: a pill that fills under the pointer and stays
/// filled for the current section.
struct NavPill: View {
    let title: String
    let isCurrent: Bool
    /// A planned section is shown in a weaker tone.
    let isPlanned: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(background, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(HB.Motion.quick, value: hovering)
        .animation(HB.Motion.quick, value: isCurrent)
        .help(isPlanned ? "\(title): planned for a later version" : title)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var foreground: Color {
        if isCurrent || hovering { return HB.Palette.text }
        return isPlanned ? HB.Palette.textTertiary : HB.Palette.textSecondary
    }

    private var background: Color {
        if isCurrent { return HB.Palette.active }
        return hovering ? HB.Palette.hover : .clear
    }
}

/// A choice of a few views, drawn as the pills of the top bar, so that no
/// system accent color appears in the content.
struct PillSegments<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                NavPill(title: option.title, isCurrent: selection == option.value, isPlanned: false) {
                    selection = option.value
                }
            }
        }
        .padding(2)
        .background(HB.Palette.surface, in: Capsule())
        .accessibilityElement(children: .contain)
    }
}

/// A soft-fill card without a border. As a button it darkens a little under
/// the pointer and its arrow moves to the right.
struct Card<Content: View>: View {
    let label: String
    var action: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let interactive = action != nil
        let body = VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label).hbLabel()
                Spacer()
                if interactive {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(hovering ? HB.Palette.text : HB.Palette.textTertiary)
                        .offset(x: hovering && !reduceMotion ? 3 : 0)
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering && interactive ? HB.Palette.surfaceHover : HB.Palette.surface,
                    in: RoundedRectangle(cornerRadius: HB.Radius.large, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: HB.Radius.large, style: .continuous))
        .onHover { hovering = $0 }
        .animation(HB.Motion.quick, value: hovering)

        if let action {
            Button(action: action) { body }.buttonStyle(.plain)
        } else {
            body
        }
    }
}

/// The logo: a block of storage with one piece cut out of the top right
/// corner, and the byte that left. Drawn on the 64 unit grid of the logo.
struct LogoMark: View {
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            Block().fill(HB.Palette.text)
            Byte().fill(HB.Palette.brand)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Maps the grid area of the mark (8...56) to the view.
    private static func transform(_ rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width, rect.height) / 48
        return CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -8, y: -8)
    }

    private struct Block: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 21, y: 8))
            path.addArc(tangent1End: CGPoint(x: 32.5, y: 8), tangent2End: CGPoint(x: 32.5, y: 31.5), radius: 3.5)
            path.addArc(tangent1End: CGPoint(x: 32.5, y: 31.5), tangent2End: CGPoint(x: 56, y: 31.5), radius: 11)
            path.addArc(tangent1End: CGPoint(x: 56, y: 31.5), tangent2End: CGPoint(x: 56, y: 56), radius: 3.5)
            path.addArc(tangent1End: CGPoint(x: 56, y: 56), tangent2End: CGPoint(x: 8, y: 56), radius: 13)
            path.addArc(tangent1End: CGPoint(x: 8, y: 56), tangent2End: CGPoint(x: 8, y: 8), radius: 13)
            path.addArc(tangent1End: CGPoint(x: 8, y: 8), tangent2End: CGPoint(x: 32.5, y: 8), radius: 13)
            path.closeSubpath()
            return path.applying(LogoMark.transform(rect))
        }
    }

    private struct Byte: Shape {
        func path(in rect: CGRect) -> Path {
            Path(roundedRect: CGRect(x: 37, y: 8, width: 19, height: 19), cornerRadius: 6.5)
                .applying(LogoMark.transform(rect))
        }
    }
}
