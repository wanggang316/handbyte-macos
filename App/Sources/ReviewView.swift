import HandbyteCore
import HandbyteUI
import SwiftUI

/// The Clean review screen on the section layout of Apps: header, then the
/// grouped list, a divider and the detail pane, then the footer. Selection
/// for cleanup is the checkbox; the highlighted row only drives the detail
/// pane. The screen adds nothing to the window toolbar (ADR 001).
struct ReviewView: View {
    private enum Focus {
        case search
        case list
    }

    @Environment(AppStore.self) private var store
    @State private var outline = ReviewOutline()
    @FocusState private var focus: Focus?

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            header(sortOrder: $store.reviewList.sortOrder, query: $store.reviewList.query)
            HStack(spacing: 0) {
                list
                Rectangle().fill(HB.Palette.border).frame(width: 1)
                Group {
                    if let candidate = highlightedCandidate {
                        CandidateDetailView(candidate: candidate)
                    } else {
                        Text("Select an item to see its path, rule, activity and recovery notes.")
                            .font(HB.Typography.body)
                            .foregroundStyle(HB.Palette.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 320)
            }
            footer
        }
        .sheet(isPresented: $store.isConfirming) {
            ConfirmSheet(candidates: store.selection.selectedCandidates)
        }
    }

    private var highlightedCandidate: Candidate? {
        guard let id = outline.highlightedCandidateID else { return nil }
        return store.reviewList.candidates.first { $0.id == id }
    }

    // MARK: Header

    private func header(sortOrder: Binding<ReviewList.SortOrder>, query: Binding<String>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Clean").font(HB.Typography.title).foregroundStyle(HB.Palette.text)
                Text(summary)
                    .font(HB.Typography.body)
                    .monospacedDigit()
                    .foregroundStyle(HB.Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            PillSegments(options: [(ReviewList.SortOrder.size, "Size"), (.name, "Name")], selection: sortOrder)
                .help("Sort candidates by size or name")
            RescanButton(action: store.startScan)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(HB.Palette.textTertiary).accessibilityHidden(true)
                TextField("Search path or rule", text: query)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .search)
                    .frame(width: 150)
            }
            .font(HB.Typography.body)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(HB.Palette.surface, in: Capsule())
        }
        .padding(.horizontal, HB.Space.page)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(HB.Palette.border).frame(height: 1) }
        .background {
            // ⌘F has no menu item; a button without size carries the shortcut.
            Button("Find") { focus = .search }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private var summary: String {
        let list = store.reviewList
        let items = list.totalCount == 1 ? "1 item" : "\(list.totalCount) items"
        return "\(items) · \(ByteFormat.string(list.totalBytes))"
    }

    // MARK: List

    private var list: some View {
        @Bindable var store = store
        let groups = store.reviewList.groups
        return ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(groups) { group in
                    let isExpanded = outline.isExpanded(group.category)
                    GroupHeader(group: group, isExpanded: isExpanded,
                                isHighlighted: outline.highlighted == .group(group.category),
                                selection: $store.selection) {
                        outline.toggleExpansion(group.category, in: store.reviewList)
                        focus = .list
                    }
                    .id(ReviewListItem.group(group.category))
                    if isExpanded {
                        ForEach(group.candidates) { candidate in
                            CandidateRow(candidate: candidate,
                                         isHighlighted: outline.highlighted == .candidate(candidate.id),
                                         selection: $store.selection) {
                                outline.highlighted = .candidate(candidate.id)
                                focus = .list
                            }
                            .id(ReviewListItem.candidate(candidate.id))
                        }
                    }
                }
            }
            .padding(10)
        }
        .keyboardSelection(outline.items(in: store.reviewList), selection: $outline.highlighted,
                           open: { _ in outline.moveIn(in: store.reviewList) },
                           back: { outline.moveOut(in: store.reviewList) })
        .focused($focus, equals: .list)
        .onKeyPress(.space) {
            switch outline.highlighted {
            case .candidate(let id):
                store.selection.toggle(id)
            case .group(let category):
                guard store.selection.hasBulkSelectable(category) else { return .ignored }
                store.selection.toggleGroup(category)
            case nil:
                return .ignored
            }
            return .handled
        }
        .onChange(of: store.reviewList) { _, list in
            outline.dropHiddenHighlight(in: list)
        }
        .overlay {
            if store.reviewList.totalCount == 0 {
                ContentUnavailableView("Nothing to clean", systemImage: "checkmark.seal",
                                       description: Text("No candidate reached the minimum size."))
            } else if store.reviewList.visibleCount == 0 {
                ContentUnavailableView.search(text: store.reviewList.query)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Select All Safe") { store.selection.selectAllSafe() }
                .help("Select every eligible candidate whose rule is marked safe")
            Button("Clear") { store.selection.clear() }
                .disabled(store.selection.selectedIDs.isEmpty)
            if case .reviewing(let result) = store.phase, result.cancelled {
                Label("Scan cancelled: the list is incomplete", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(HB.Palette.review)
            }
            if store.scanLackedFullDiskAccess {
                MissingAccessNote()
            }
            Spacer()
            Text("\(store.selection.selectedIDs.count) selected, \(ByteFormat.string(store.selection.selectedBytes))")
                .monospacedDigit()
                .foregroundStyle(HB.Palette.textSecondary)
            if store.deletionMode == .removePermanently {
                Button("Delete Permanently…", role: .destructive, action: store.requestConfirmation)
                    .tint(HB.Palette.danger)
                    .disabled(store.selection.selectedIDs.isEmpty)
            } else {
                Button(store.deletionMode == .trash ? "Move to Trash…" : "Clean…", action: store.requestConfirmation)
                    .disabled(store.selection.selectedIDs.isEmpty)
            }
        }
        .font(HB.Typography.body)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(HB.Palette.border).frame(height: 1) }
    }
}

/// Rescan in the header: an icon and a label on the soft fill of the search field.
private struct RescanButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label("Rescan", systemImage: "arrow.clockwise")
                .font(HB.Typography.body)
                .foregroundStyle(hovering ? HB.Palette.text : HB.Palette.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(hovering ? HB.Palette.surfaceHover : HB.Palette.surface, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .hbAnimation(HB.Motion.quick, value: hovering)
        .help("Scan again")
    }
}

/// A checkbox drawn with the design tokens, so no system accent color
/// appears in the list.
private struct Checkbox: View {
    enum State {
        case off
        case mixed
        case on
    }

    let state: State
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(state == .off ? HB.Palette.textTertiary : HB.Palette.brand)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hbFocusRing()
        .accessibilityLabel(label)
        .accessibilityValue(state == .on ? "selected" : state == .mixed ? "partly selected" : "not selected")
    }

    private var symbol: String {
        switch state {
        case .off: "square"
        case .mixed: "minus.square.fill"
        case .on: "checkmark.square.fill"
        }
    }
}

private struct GroupHeader: View {
    let group: CandidateGroup
    let isExpanded: Bool
    let isHighlighted: Bool
    @Binding var selection: Selection
    let toggleExpansion: () -> Void
    @State private var hovering = false

    var body: some View {
        let canBulkSelect = selection.hasBulkSelectable(group.category)
        HStack(spacing: 8) {
            Checkbox(state: checkboxState, label: "Select all safe items in \(group.category.rawValue)") {
                selection.toggleGroup(group.category)
            }
            .disabled(!canBulkSelect)
            .opacity(canBulkSelect ? 1 : 0.4)
            .help("Select every safe item in this group; review and hold items are skipped")
            // Only the part after the checkbox collapses the group, so a click
            // on a disabled checkbox does not fall through to it.
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HB.Palette.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(group.category.rawValue).hbLabel()
                Text("\(group.candidates.count)")
                    .font(HB.Typography.label)
                    .monospacedDigit()
                    .foregroundStyle(HB.Palette.textTertiary)
                Spacer()
                Text(totalText)
                    .font(HB.Typography.body)
                    .monospacedDigit()
                    .foregroundStyle(HB.Palette.textSecondary)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggleExpansion)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .hbRowBackground(isHighlighted: isHighlighted, hovering: hovering)
        .onHover { hovering = $0 }
        .hbAnimation(HB.Motion.quick, value: hovering)
        .hbAnimation(HB.Motion.quick, value: isExpanded)
        // One element, so VoiceOver reads the expanded state and its default
        // action collapses or expands; the checkbox becomes a named action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.category.rawValue), \(group.candidates.count == 1 ? "1 item" : "\(group.candidates.count) items"), \(totalText)")
        .accessibilityValue("\(isExpanded ? "expanded" : "collapsed"), \(selectionDescription)")
        .accessibilityAddTraits(isHighlighted ? [.isHeader, .isButton, .isSelected] : [.isHeader, .isButton])
        .accessibilityAction { toggleExpansion() }
        .accessibilityActions {
            if canBulkSelect {
                Button(selection.groupState(group.category) == .all ? "Deselect Safe Items" : "Select Safe Items") {
                    selection.toggleGroup(group.category)
                }
            }
        }
    }

    private var selectionDescription: String {
        switch selection.groupState(group.category) {
        case .none: "no items selected"
        case .some: "some items selected"
        case .all: "all safe items selected"
        }
    }

    private var totalText: String {
        group.partial ? "≥ \(ByteFormat.string(group.totalBytes))" : ByteFormat.string(group.totalBytes)
    }

    private var checkboxState: Checkbox.State {
        switch selection.groupState(group.category) {
        case .none: .off
        case .some: .mixed
        case .all: .on
        }
    }
}

private struct CandidateRow: View {
    let candidate: Candidate
    let isHighlighted: Bool
    @Binding var selection: Selection
    let highlight: () -> Void
    @Environment(AppStore.self) private var store
    @State private var hovering = false

    var body: some View {
        let isBlocked = candidate.eligibility.blockedReason != nil
        HStack(spacing: 10) {
            Checkbox(state: selection.isSelected(candidate.id) ? .on : .off,
                     label: "Select \(candidate.url.lastPathComponent)") {
                selection.toggle(candidate.id)
            }
            .disabled(!selection.canSelect(candidate))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(candidate.url.lastPathComponent)
                        .foregroundStyle(HB.Palette.text)
                        .lineLimit(1)
                    SafetyBadge(safety: candidate.rule.safety)
                    if let reason = candidate.eligibility.blockedReason {
                        BlockedBadge(reason: reason)
                    }
                }
                Text(candidate.url.deletingLastPathComponent().fileSystemPath)
                    .font(.system(size: 11))
                    .foregroundStyle(HB.Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(ByteFormat.string(candidate.size))
                .monospacedDigit()
                .foregroundStyle(hovering || isHighlighted ? HB.Palette.text : HB.Palette.textSecondary)
        }
        .font(HB.Typography.body)
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .frame(height: 44)
        .opacity(isBlocked ? 0.6 : 1)
        .hbRowBackground(isHighlighted: isHighlighted, hovering: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: highlight)
        .hbAnimation(HB.Motion.quick, value: hovering)
        .contextMenu {
            Button("Reveal in Finder") { store.reveal(candidate) }
            Button("Never Clean This") { store.exclude(candidate) }
                .disabled(store.isExcluded(candidate))
        }
        // One element, so the default action of VoiceOver highlights the row
        // and shows its details; the checkbox becomes a named action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selection.isSelected(candidate.id) ? "selected for cleanup" : "not selected")
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { highlight() }
        .accessibilityActions {
            if selection.canSelect(candidate) {
                Button(selection.isSelected(candidate.id) ? "Deselect" : "Select") { selection.toggle(candidate.id) }
            }
            Button("Reveal in Finder") { store.reveal(candidate) }
        }
    }

    private var accessibilityLabel: String {
        // The folder tells apart items with the same name, such as two node_modules.
        var parts = [candidate.url.lastPathComponent, "in \(candidate.url.deletingLastPathComponent().fileSystemPath)",
                     "Safety: \(SafetyBadge.label(candidate.rule.safety))", ByteFormat.string(candidate.size)]
        if let reason = candidate.eligibility.blockedReason { parts.append("blocked: \(reason)") }
        return parts.joined(separator: ", ")
    }
}

struct CandidateDetailView: View {
    @Environment(AppStore.self) private var store
    let candidate: Candidate

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(candidate.url.lastPathComponent)
                                .font(HB.Typography.head)
                                .foregroundStyle(HB.Palette.text)
                                .lineLimit(2)
                            SafetyBadge(safety: candidate.rule.safety)
                        }
                        Text(candidate.url.fileSystemPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(HB.Palette.textTertiary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let reason = candidate.eligibility.blockedReason {
                        Label("Blocked: \(reason). This item cannot be selected.", systemImage: "lock.fill")
                            .font(HB.Typography.body)
                            .foregroundStyle(HB.Palette.textSecondary)
                    } else if let reason = candidate.eligibility.reviewOnlyReason {
                        Label("Hold: \(reason). Excluded from bulk selection; select it one by one.", systemImage: "hand.raised.fill")
                            .font(HB.Typography.body)
                            .foregroundStyle(HB.Palette.danger)
                    }
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                        fact("Size", ByteFormat.string(candidate.size)
                            + (candidate.size.partial ? " (lower bound, \(candidate.size.errorCount) unreadable entries)" : ""))
                        fact("Files", candidate.size.fileCount.formatted())
                        fact("Last activity", lastActivity)
                        fact("Rule", candidate.rule.id)
                        fact("Category", candidate.rule.category.rawValue)
                    }
                    note("What it is", candidate.rule.summary)
                    note("After removal", candidate.rule.recovery)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            HStack {
                Button("Reveal in Finder") { store.reveal(candidate) }
                Spacer()
                Button("Never Clean This") { store.exclude(candidate) }
                    .disabled(store.isExcluded(candidate))
                    .help("Add this path to the exclusion list. It stays blocked on every scan until removed in Settings.")
            }
            .padding(14)
            .overlay(alignment: .top) { Rectangle().fill(HB.Palette.border).frame(height: 1) }
        }
    }

    private var lastActivity: String {
        guard let date = candidate.lastActivity else { return "Unknown" }
        let relative = date.formatted(.relative(presentation: .named))
        return "\(relative) (\(date.formatted(date: .abbreviated, time: .shortened)))"
    }

    private func fact(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(HB.Palette.textTertiary)
            Text(value)
                .foregroundStyle(HB.Palette.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(HB.Typography.body)
    }

    private func note(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).hbLabel()
            Text(text)
                .font(HB.Typography.body)
                .foregroundStyle(HB.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
