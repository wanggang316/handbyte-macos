import HandbyteCore
import HandbyteUI
import SwiftUI

/// Smart Clean on one screen: scan, confirm, clean and result. The large
/// number keeps its place in every phase, so the screen does not jump.
struct SmartCleanView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                switch store.phase {
                case .idle:
                    start
                case .scanning(let monitor):
                    scanning(monitor)
                case .reviewing, .confirming:
                    if let plan = store.smartPlan {
                        ready(plan)
                    }
                case .cleaning(let run):
                    cleaning(run)
                case .report(let report):
                    result(report)
                }
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, HB.Space.page)
            .padding(.top, 44)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .hbAnimation(HB.Motion.standard, value: phaseKey)
    }

    private var phaseKey: Int {
        switch store.phase {
        case .idle: 0
        case .scanning: 1
        case .reviewing, .confirming: 2
        case .cleaning: 3
        case .report: 4
        }
    }

    // MARK: Phases

    private var start: some View {
        VStack(spacing: 14) {
            Hero(status: "Ready", live: false, value: nil, label: "Smart Clean")
            Text("Scans the caches, logs and build data that apps make again by themselves, then cleans them after one confirmation.")
                .font(.system(size: 14))
                .foregroundStyle(HB.Palette.textSecondary)
                .multilineTextAlignment(.center)
            Button("Scan now", action: store.startScan)
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
            Button("Choose items", action: store.chooseItems)
                .buttonStyle(LinkButtonStyle())
        }
    }

    private func scanning(_ monitor: ScanMonitor) -> some View {
        let found = monitor.found.reduce(Int64(0)) { $0 + $1.size.allocatedBytes }
        let finished = monitor.rows.filter { if case .finished = $0.state { true } else { false } }.count
        return VStack(spacing: 24) {
            TimelineView(.periodic(from: store.scanStartedAt, by: 0.2)) { context in
                let seconds = max(0.1, context.date.timeIntervalSince(store.scanStartedAt))
                VStack(spacing: 10) {
                    Hero(status: "Scanning · \(finished) of \(monitor.rows.count) groups", live: true, value: found, label: "found so far")
                    Text("\(monitor.filesSeen.formatted()) files · \(Int(Double(monitor.filesSeen) / seconds).formatted()) files per second · \(seconds.formatted(.number.precision(.fractionLength(1)))) s")
                        .font(HB.Typography.body)
                        .monospacedDigit()
                        .foregroundStyle(HB.Palette.textTertiary)
                }
            }
            ProgressLine(fraction: monitor.rows.isEmpty ? 0 : Double(finished) / Double(monitor.rows.count))
            VStack(spacing: 0) {
                ForEach(Catalog.areas, id: \.id) { area in
                    let items = monitor.found.filter { $0.rule.area == area.id }
                    let bytes = items.reduce(Int64(0)) { $0 + $1.size.allocatedBytes }
                    AreaRow(
                        state: items.isEmpty ? .waiting : .busy,
                        title: area.title,
                        detail: items.isEmpty ? nil : items.last.map { $0.url.fileSystemPath },
                        size: items.isEmpty ? nil : ByteFormat.string(bytes) + "+"
                    )
                }
            }
            Button("Stop and use what was found", action: store.cancelScan)
                .buttonStyle(LinkButtonStyle())
                .keyboardShortcut(.cancelAction)
            Text("Fast areas finish first. You can change sections; the scan continues.")
                .font(.system(size: 12))
                .foregroundStyle(HB.Palette.textTertiary)
        }
    }

    private func ready(_ plan: SmartCleanPlan) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Hero(status: "Scan complete", live: false, value: plan.safeBytes, label: "safe to clean")
                Text(plan.selection.isEmpty
                    ? "Nothing safe to clean was found."
                    : "\(plan.selection.count == 1 ? "1 item" : "\(plan.selection.count) items") in \(plan.areas.filter { $0.safeCount > 0 }.count == 1 ? "1 area" : "\(plan.areas.filter { $0.safeCount > 0 }.count) areas"). No documents, no settings, no history.")
                    .font(HB.Typography.body)
                    .foregroundStyle(HB.Palette.textTertiary)
            }
            ProgressLine(fraction: 1)
            VStack(spacing: 0) {
                ForEach(plan.areas) { area in
                    AreaRow(
                        state: area.safeCount > 0 ? .done : .idle,
                        title: area.title,
                        detail: note(area),
                        size: area.safeCount > 0 ? ByteFormat.string(area.safeBytes) : "—"
                    )
                }
            }
            if store.systemBytes > 0 || store.systemMessage != nil {
                HStack(spacing: 12) {
                    Image(systemName: "lock").foregroundStyle(HB.Palette.textTertiary).frame(width: 18).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Old system logs").foregroundStyle(HB.Palette.text)
                        Text(store.systemMessage ?? "Old crash reports and logs of macOS. They belong to the system, so macOS asks for your password.")
                            .font(.system(size: 11)).foregroundStyle(HB.Palette.textTertiary)
                    }
                    Spacer()
                    if store.systemBytes > 0 {
                        Text(ByteFormat.string(store.systemBytes)).monospacedDigit().foregroundStyle(HB.Palette.textSecondary)
                        Button(store.isCleaningSystem ? "Cleaning…" : "Clean with Password…", action: store.cleanSystem)
                            .disabled(store.isCleaningSystem)
                    }
                }
                .font(HB.Typography.body)
                .padding(.horizontal, 6)
            }
            ForEach(store.reviewSystemRules) { item in
                ReviewSystemRow(item: item)
            }
            VStack(spacing: 12) {
                Button("Clean \(ByteFormat.string(plan.safeBytes))", action: store.cleanSmart)
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan.selection.isEmpty)
                HStack(spacing: 18) {
                    if plan.reviewBytes > 0 {
                        Button("Choose items · \(ByteFormat.string(plan.reviewBytes)) needs review", action: store.chooseItems)
                            .buttonStyle(LinkButtonStyle())
                    } else {
                        Button("Choose items", action: store.chooseItems)
                            .buttonStyle(LinkButtonStyle())
                    }
                    Button("Scan again", action: store.startScan)
                        .buttonStyle(LinkButtonStyle())
                }
                Text(store.deletionMode == .trash
                    ? "Safe items move to the Trash. Empty the Trash to free the space."
                    : "Caches and logs are removed; apps make them again when needed.")
                    .font(.system(size: 12))
                    .foregroundStyle(HB.Palette.textTertiary)
            }
            .hbTransition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private func note(_ area: SmartCleanPlan.Area) -> String? {
        var parts: [String] = []
        if area.safeCount > 0 { parts.append(area.safeCount == 1 ? "1 item" : "\(area.safeCount) items") }
        if area.reviewBytes > 0 { parts.append("\(ByteFormat.string(area.reviewBytes)) needs review") }
        if area.skippedBytes > 0 {
            parts.append("\(ByteFormat.string(area.skippedBytes)) skipped" + (area.skippedReason.map { ": \($0)" } ?? ""))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func cleaning(_ run: CleanRun) -> some View {
        let plan = store.smartPlanInFlight
        let doneIDs = Set(run.outcomes.map(\.candidate.id))
        return VStack(spacing: 24) {
            Hero(status: "Cleaning", live: true, value: run.bytesClaimed, label: "freed")
            ProgressLine(fraction: Double(run.completed) / Double(max(1, run.total)))
            VStack(spacing: 0) {
                ForEach(plan?.areas.filter { $0.safeCount > 0 } ?? []) { area in
                    let items = plan?.selection.filter { $0.rule.area == area.id } ?? []
                    let finished = items.allSatisfy { doneIDs.contains($0.id) }
                    AreaRow(
                        state: finished ? .done : .busy,
                        title: area.title,
                        detail: finished ? "Cleaned" : "Checking again, then cleaning",
                        size: ByteFormat.string(area.safeBytes)
                    )
                }
            }
            Button("Stop after the current item", action: store.cancelClean)
                .buttonStyle(LinkButtonStyle())
        }
    }

    private func result(_ report: CleanReport) -> some View {
        let removed = report.removed.reduce(Int64(0)) { $0 + $1.candidate.size.allocatedBytes }
        let moved = report.moved.reduce(Int64(0)) { $0 + $1.candidate.size.allocatedBytes }
        let plan = store.smartPlanInFlight
        return VStack(spacing: 24) {
            VStack(spacing: 10) {
                Hero(status: report.isPartial ? "Stopped" : "Done", live: false, value: removed > 0 ? removed : moved, label: removed > 0 ? "freed" : "moved to the Trash")
                if let before = store.freeBeforeClean, let after = store.volume?.availableBytes {
                    Text("Free space: \(ByteFormat.string(before)) → \(ByteFormat.string(after))")
                        .font(HB.Typography.body)
                        .monospacedDigit()
                        .foregroundStyle(HB.Palette.textTertiary)
                }
                if removed > 0, moved > 0 {
                    Text("\(ByteFormat.string(moved)) moved to the Trash")
                        .font(HB.Typography.body)
                        .foregroundStyle(HB.Palette.textTertiary)
                }
            }
            ProgressLine(fraction: 1)
            if let plan {
                let skippedIDs = Set((report.skipped + report.failed + report.notAttempted).map(\.candidate.id))
                VStack(spacing: 0) {
                    ForEach(plan.areas.filter { $0.safeCount > 0 }) { area in
                        let items = plan.selection.filter { $0.rule.area == area.id }
                        let missed = items.filter { skippedIDs.contains($0.id) }.count
                        AreaRow(
                            state: missed == items.count ? .idle : .done,
                            title: area.title,
                            detail: missed == 0 ? (store.deletionMode == .trash ? "Moved to the Trash" : "Cleaned") : "\(items.count - missed) cleaned · \(missed) skipped",
                            size: ByteFormat.string(area.safeBytes)
                        )
                    }
                }
            }
            if !report.skipped.isEmpty || !report.failed.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(report.skipped + report.failed) { item in
                        Label("\(item.candidate.url.lastPathComponent): \(item.detail ?? "skipped")", systemImage: "exclamationmark.circle")
                            .font(HB.Typography.body)
                            .foregroundStyle(HB.Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button("Done") { store.section = .overview }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
                if let review = plan?.reviewBytes, review > 0 {
                    Button("Review \(ByteFormat.string(review)) more", action: store.chooseItems)
                        .buttonStyle(LinkButtonStyle())
                }
            }
            .hbTransition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }
}

/// The status line, the large number and its label.
private struct Hero: View {
    let status: String
    let live: Bool
    let value: Int64?
    let label: String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                LiveDot(live: live)
                Text(status)
                    .font(HB.Typography.body)
                    .foregroundStyle(HB.Palette.textTertiary)
            }
            if let value {
                (Text(ByteFormat.string(value))
                    .font(HB.Typography.hero)
                    .tracking(-2.5)
                    .foregroundStyle(HB.Palette.text)
                    + Text("  \(label)")
                    .font(HB.Typography.title)
                    .foregroundStyle(HB.Palette.textSecondary))
                    .monospacedDigit()
                    .hbNumericTransition()
                    .multilineTextAlignment(.center)
            } else {
                Text(label)
                    .font(HB.Typography.hero)
                    .tracking(-2.5)
                    .foregroundStyle(HB.Palette.text)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A dot that pulses while something runs. With Reduce Motion it stays still.
private struct LiveDot: View {
    let live: Bool
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(live ? HB.Palette.brand : HB.Palette.borderStrong)
            .frame(width: 8, height: 8)
            .opacity(live && pulse && !reduceMotion ? 0.35 : 1)
            .accessibilityHidden(true)
            .onAppear {
                guard live, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

/// A thin progress line in the brand color.
struct ProgressLine: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(HB.Palette.surfaceHover)
                Capsule()
                    .fill(HB.Palette.brand)
                    .frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 3)
        .hbAnimation(HB.Motion.standard, value: fraction)
        .accessibilityElement()
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

/// One area of a cleanup: waiting, busy, done or idle, with a size.
private struct AreaRow: View {
    enum State { case waiting, busy, done, idle }

    let state: State
    let title: String
    let detail: String?
    let size: String?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(HB.Palette.brand)
                case .busy:
                    ProgressView().controlSize(.small)
                case .waiting, .idle:
                    Circle().fill(HB.Palette.borderStrong).frame(width: 6, height: 6)
                }
            }
            .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(state == .waiting ? HB.Palette.textTertiary : HB.Palette.text)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(HB.Palette.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if let size {
                Text(size)
                    .monospacedDigit()
                    .fontWeight(.medium)
                    .foregroundStyle(hovering ? HB.Palette.text : HB.Palette.textSecondary)
            }
        }
        .font(HB.Typography.body)
        .padding(.horizontal, 6)
        .frame(minHeight: 46)
        .background(hovering ? HB.Palette.hover : .clear, in: RoundedRectangle(cornerRadius: HB.Radius.small, style: .continuous))
        .overlay(alignment: .bottom) { Rectangle().fill(HB.Palette.border).frame(height: 1) }
        .onHover { hovering = $0 }
        .hbAnimation(HB.Motion.quick, value: hovering)
        .accessibilityElement(children: .combine)
    }
}

/// A system rule that needs its own confirmation, such as the erase of the
/// unified log. It is never part of Clean.
private struct ReviewSystemRow: View {
    let item: AppStore.ReviewSystemRule
    @Environment(AppStore.self) private var store
    @State private var confirming = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock").foregroundStyle(HB.Palette.textTertiary).frame(width: 18).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.rule.title).foregroundStyle(HB.Palette.text)
                Text(item.message ?? "Needs review. \(item.rule.summary)")
                    .font(.system(size: 11)).foregroundStyle(HB.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if item.bytes > 0 {
                Text(ByteFormat.string(item.bytes)).monospacedDigit().foregroundStyle(HB.Palette.textSecondary)
                Button("Erase…") { confirming = true }
                    .disabled(store.isCleaningSystem)
                    .confirmationDialog("Erase the \(item.rule.title.lowercased())?", isPresented: $confirming) {
                        Button("Erase with Password", role: .destructive) { store.cleanSystem(review: item.id) }
                    } message: {
                        Text("\(item.rule.recovery) The command is \(item.rule.shellCommand), run as root after the macOS password dialog.")
                    }
            }
        }
        .font(HB.Typography.body)
        .padding(.horizontal, 6)
    }
}
