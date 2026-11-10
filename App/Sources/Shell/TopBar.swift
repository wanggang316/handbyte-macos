import HandbyteUI
import SwiftUI

/// The tabs of the window toolbar. There is no sidebar: the sections are a
/// row of pills, and the content below is one column.
struct SectionTabs: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppSection.allCases) { section in
                NavPill(title: section.title, isCurrent: store.section == section, isPlanned: false) {
                    store.section = section
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sections")
    }
}

/// The mark and the name, at the leading edge of the toolbar.
struct Wordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            LogoMark(size: 18)
            Text("Handbyte")
                .font(HB.Typography.head)
                .foregroundStyle(HB.Palette.text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Handbyte")
    }
}
