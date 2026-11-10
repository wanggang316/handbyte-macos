import HandbyteUI
import SwiftUI

/// The tabs of the window toolbar. There is no sidebar: the sections are a
/// row of pills, and the content below is one column.
struct SectionTabs: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppSection.allCases) { section in
                NavPill(
                    title: section.title,
                    isCurrent: store.section == section,
                    isPlanned: !section.isAvailable
                ) {
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

/// Shown for a section that is planned but not built yet.
struct PlannedView: View {
    let section: AppSection

    var body: some View {
        VStack(spacing: 10) {
            Text("Planned").hbLabel()
            Text(section.title)
                .font(HB.Typography.title)
                .foregroundStyle(HB.Palette.text)
            Text(section.plannedSummary)
                .font(.system(size: 14))
                .foregroundStyle(HB.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Text("This section is not in this version.")
                .font(HB.Typography.body)
                .foregroundStyle(HB.Palette.textTertiary)
        }
        .padding(HB.Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
