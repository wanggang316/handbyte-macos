import HandbyteUI
import SwiftUI

/// The first screen: one sentence, one number and one action.
struct OverviewView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let summary = store.overview
        ScrollView {
            VStack(spacing: HB.Space.section) {
                hero(summary)
                if let volume = store.volume {
                    volumeSection(volume)
                }
                cards(summary)
            }
            .frame(maxWidth: HB.Space.column)
            .padding(.horizontal, HB.Space.page)
            .padding(.top, 48)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .onAppear(perform: store.refreshVolume)
    }

    // MARK: Hero

    private func hero(_ summary: OverviewSummary) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(store.isScanning ? HB.Palette.brand : HB.Palette.borderStrong)
                    .frame(width: 8, height: 8)
                Text(store.isScanning ? "Scanning" : summary.detail)
                    .font(HB.Typography.body)
                    .foregroundStyle(HB.Palette.textTertiary)
            }
            if let bytes = summary.heroBytes {
                // One text, so that the number and its label wrap as a unit
                // and VoiceOver reads them together.
                (Text(ByteFormat.string(bytes))
                    .font(HB.Typography.hero)
                    .tracking(-2.5)
                    .foregroundStyle(HB.Palette.text)
                    + Text("  \(summary.heroLabel)")
                    .font(HB.Typography.title)
                    .foregroundStyle(HB.Palette.textSecondary))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .contentTransition(.numericText())
            }
            Text(sentence(summary))
                .font(.system(size: 14))
                .foregroundStyle(HB.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button(primaryTitle(summary), action: primaryAction(summary))
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
                .padding(.top, 10)
            if summary.primaryAction == .review {
                Button("Scan again", action: store.scanFromOverview)
                    .buttonStyle(LinkButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sentence(_ summary: OverviewSummary) -> String {
        switch summary.primaryAction {
        case .scan:
            "Find caches and build output that apps make again when they need them. You see each item before anything is removed."
        case .review:
            "Caches and build output that apps make again when they need them. You choose the items in the next step."
        }
    }

    private func primaryTitle(_ summary: OverviewSummary) -> String {
        if store.isScanning { return "Show the scan" }
        return summary.primaryAction == .review ? "Review and clean" : "Scan now"
    }

    private func primaryAction(_ summary: OverviewSummary) -> () -> Void {
        if store.isScanning || summary.primaryAction == .review {
            return { store.section = .clean }
        }
        return store.scanFromOverview
    }

    // MARK: Volume

    private func volumeSection(_ volume: VolumeUsage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            (Text("\(ByteFormat.string(volume.availableBytes)) free")
                .fontWeight(.semibold)
                .foregroundStyle(HB.Palette.text)
                + Text(" of \(ByteFormat.string(volume.totalBytes))\(store.volumeName.map { " on \($0)" } ?? "")")
                .foregroundStyle(HB.Palette.textTertiary))
                .font(HB.Typography.body)
                .monospacedDigit()
            let summary = store.storage.lastSummary
            CategoryMeter(
                parts: VolumeBreakdown.parts(volume: volume, home: summary).map { .init(id: $0.id, title: $0.title, bytes: $0.bytes) },
                total: volume.totalBytes,
                showsLegend: summary != nil
            )
            if summary == nil {
                Button("Open Storage to see what fills the disk") { store.section = .storage }
                    .buttonStyle(LinkButtonStyle())
            }
        }
    }

    // MARK: Cards

    private func cards(_ summary: OverviewSummary) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
            Card(label: "Needs your review", action: summary.reviewBytes > 0 ? { store.section = .clean } : nil) {
                cardBody(
                    value: summary.reviewBytes > 0 ? ByteFormat.string(summary.reviewBytes) : "No items",
                    text: summary.reviewBytes > 0
                        ? "Items that are not safe to clean without a look."
                        : "A scan lists the items that need a look before they are cleaned."
                )
            }
            Card(label: "Apps", action: { store.section = .apps }) {
                cardBody(value: "Planned", text: "App sizes, last use and uninstall with leftovers.")
            }
            Card(label: "Storage", action: { store.section = .storage }) {
                cardBody(
                    value: store.storage.lastSummary.map { "\(ByteFormat.string($0.allocatedBytes)) in home" }
                        ?? store.volume.map { "\(ByteFormat.string($0.usedBytes)) used" } ?? "Storage",
                    text: store.storage.lastSummary.map { "Measured \($0.scannedAt.formatted(.relative(presentation: .named)))." }
                        ?? "See what fills your home folder, folder by folder."
                )
            }
        }
    }

    private func cardBody(value: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(HB.Typography.title)
                .monospacedDigit()
                .foregroundStyle(HB.Palette.text)
                .padding(.top, 8)
            Text(text)
                .font(HB.Typography.body)
                .foregroundStyle(HB.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
