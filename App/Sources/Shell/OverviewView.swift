import HandbyteUI
import SwiftUI

/// The first screen: one sentence, one number and one action.
struct OverviewView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let summary = store.overview
        ScrollView {
            VStack(spacing: HB.Space.section) {
                if !store.settings.hasSeenIntro {
                    intro
                }
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

    // MARK: First run

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How Handbyte works").hbLabel()
            introLine("checkmark.circle", "Clean now takes only safe items: caches, logs and build output that apps make again by themselves.")
            introLine("tray.full", "Those are removed, so the space is free at once. Everything else, such as apps and backups, goes to the Trash.")
            introLine("arrow.uturn.backward", "Each action is listed in History. An item in the Trash can be put back from there.")
            HStack {
                Spacer()
                Button("Got It") { store.settings.hasSeenIntro = true }
                    .buttonStyle(LinkButtonStyle())
            }
        }
        .padding(16)
        .background(HB.Palette.surface, in: RoundedRectangle(cornerRadius: HB.Radius.large, style: .continuous))
        .transition(.opacity)
    }

    private func introLine(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(HB.Palette.brand).frame(width: 16)
            Text(text).font(HB.Typography.body).foregroundStyle(HB.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            Button(primaryTitle(summary), action: store.startSmartClean)
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
                .padding(.top, 10)
            HStack(spacing: 20) {
                Button("Choose items", action: store.chooseItems)
                    .buttonStyle(LinkButtonStyle())
                if summary.primaryAction == .review {
                    Button("Scan again", action: store.scanFromOverview)
                        .buttonStyle(LinkButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sentence(_ summary: OverviewSummary) -> String {
        switch summary.primaryAction {
        case .scan:
            "Finds the caches, logs and build data that apps make again by themselves. One confirmation, then they are cleaned."
        case .review:
            "Caches and logs that apps make again when they need them. No documents, no settings, no history."
        }
    }

    private func primaryTitle(_ summary: OverviewSummary) -> String {
        if store.isScanning { return "Show the scan" }
        if summary.primaryAction == .review, let bytes = summary.heroBytes { return "Clean \(ByteFormat.string(bytes))" }
        return "Clean now"
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
            if volume.purgeableBytes > 0 {
                Text("\(ByteFormat.string(volume.purgeableBytes)) of the free space is purgeable: macOS frees it by itself when it needs the space.")
                    .font(.system(size: 12))
                    .foregroundStyle(HB.Palette.textTertiary)
            }
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)], alignment: .center, spacing: 12) {
            Card(label: "Needs your review", action: summary.reviewBytes > 0 ? { store.chooseItems() } : nil) {
                cardBody(
                    value: summary.reviewBytes > 0 ? ByteFormat.string(summary.reviewBytes) : "No items",
                    text: summary.reviewBytes > 0
                        ? "Items that are not safe to clean without a look."
                        : "A scan lists the items that need a look before they are cleaned."
                )
            }
            Card(label: "Apps", action: { store.section = .apps }) {
                cardBody(
                    value: store.apps.hasLoaded ? "\(store.apps.browser.apps.count) apps" : "Apps",
                    text: "Size and last use of each app. Uninstall an app with the files it keeps."
                )
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
