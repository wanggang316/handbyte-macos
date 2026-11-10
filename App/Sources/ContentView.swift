import HandbyteUI
import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        // A plain stack, not a safe-area inset: a scrolling section would
        // scroll under an inset and the banner would cover its first rows.
        VStack(spacing: 0) {
            FullDiskAccessBanner()
            switch store.section {
            case .overview:
                OverviewView()
            case .clean:
                cleanFlow
            case .storage:
                StorageView()
            case .apps, .history:
                PlannedView(section: store.section)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(HB.Palette.background)
        .toolbar {
            wordmarkItem
            ToolbarItem(placement: .principal) {
                SectionTabs()
            }
        }
    }

    /// The mark and the name are not a control, so they get no toolbar
    /// background on systems that draw one behind each item.
    @ToolbarContentBuilder
    private var wordmarkItem: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) { Wordmark() }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { Wordmark() }
        }
    }

    /// The cleanup flow keeps its state when the user changes sections.
    @ViewBuilder
    private var cleanFlow: some View {
        switch store.phase {
        case .idle, .scanning:
            ScanView()
        case .reviewing, .confirming:
            ReviewView()
        case .cleaning(let run):
            CleaningView(run: run)
        case .report(let report):
            ReportView(report: report)
        }
    }
}
