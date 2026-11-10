import HandbyteCore
import HandbyteUI
import SwiftUI

/// The Storage section: what fills the home folder, folder by folder.
struct StorageView: View {
    @Environment(StorageStore.self) private var store

    var body: some View {
        Group {
            switch store.phase {
            case .idle:
                Color.clear
            case .scanning(let progress):
                StorageScanningView(progress: progress)
            case .ready(let result):
                StorageResultView(result: result)
            case .failed:
                failed
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: store.startIfNeeded)
    }

    private var failed: some View {
        VStack(spacing: 12) {
            Text("The folder cannot be read")
                .font(HB.Typography.title)
                .foregroundStyle(HB.Palette.text)
            Text(store.root.path(percentEncoded: false))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(HB.Palette.textSecondary)
            Button("Scan again", action: store.start)
                .buttonStyle(PillButtonStyle())
                .padding(.top, 8)
        }
        .padding(HB.Space.page)
    }
}

/// The scan in progress: one number that grows, and one line for each
/// top-level folder. No empty screen while the user waits.
private struct StorageScanningView: View {
    let progress: UsageProgress
    @Environment(StorageStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: store.startedAt, by: 0.1)) { context in
            let seconds = max(0.1, context.date.timeIntervalSince(store.startedAt))
            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Circle().fill(HB.Palette.brand).frame(width: 8, height: 8)
                        Text("Scanning your home folder")
                            .font(HB.Typography.body)
                            .foregroundStyle(HB.Palette.textTertiary)
                    }
                    (Text(ByteFormat.string(progress.allocatedBytes))
                        .font(HB.Typography.hero)
                        .tracking(-2.5)
                        .foregroundStyle(HB.Palette.text)
                        + Text("  found so far")
                        .font(HB.Typography.title)
                        .foregroundStyle(HB.Palette.textSecondary))
                        .monospacedDigit()
                    Text("\(progress.fileCount.formatted()) files · \(Int(Double(progress.fileCount) / seconds).formatted()) files per second · \(seconds.formatted(.number.precision(.fractionLength(1)))) s")
                        .font(HB.Typography.body)
                        .monospacedDigit()
                        .foregroundStyle(HB.Palette.textTertiary)
                    if let last = store.lastSummary {
                        Text("Last time \(ByteFormat.string(last.allocatedBytes)), \(last.scannedAt.formatted(.relative(presentation: .named)))")
                            .font(HB.Typography.body)
                            .foregroundStyle(HB.Palette.textTertiary)
                    }
                }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(progress.top.sorted { $0.allocatedBytes > $1.allocatedBytes }) { entry in
                            row(entry)
                        }
                    }
                }
                .frame(maxWidth: 640)
                Button("Stop and use what was found", action: store.stop)
                    .buttonStyle(LinkButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, HB.Space.page)
            .padding(.top, 44)
            .padding(.bottom, 24)
        }
    }

    private func row(_ entry: UsageProgress.Top) -> some View {
        let waiting = !entry.done && entry.allocatedBytes == 0
        return HStack(spacing: 12) {
            Group {
                if entry.done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(HB.Palette.brand)
                } else if waiting {
                    Circle().fill(HB.Palette.borderStrong).frame(width: 6, height: 6)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 18)
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(waiting ? HB.Palette.textTertiary : HB.Palette.text)
            Spacer()
            if !waiting {
                Text(ByteFormat.string(entry.allocatedBytes) + (entry.done ? "" : "+"))
                    .monospacedDigit()
                    .fontWeight(.medium)
                    .foregroundStyle(HB.Palette.text)
            } else if let last = store.lastSummary?.top.first(where: { $0.name == entry.name }) {
                // Until the folder is measured, its size of the last run
                // stands in, in a faint tone, so that the list is not empty.
                Text(ByteFormat.string(last.allocatedBytes))
                    .monospacedDigit()
                    .foregroundStyle(HB.Palette.textTertiary)
                    .help("Size at the last scan")
            }
        }
        .font(HB.Typography.body)
        .frame(height: 36)
        .padding(.horizontal, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(HB.Palette.border).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// The scanned tree: crumbs, a treemap of the opened folder and a side list.
private struct StorageResultView: View {
    let result: UsageResult
    @Environment(StorageStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            header(mode: $store.mode)
            CollectorBar()
            if store.mode == .folders, let browser = store.browser {
                if browser.trail.isEmpty, !store.categories.isEmpty {
                    CategoryMeter(
                        parts: store.categories.map { .init(id: $0.id, title: StorageCatalog.shared.title(of: $0.id), bytes: $0.allocatedBytes) },
                        total: browser.root.allocatedBytes
                    )
                    .padding(.horizontal, HB.Space.page)
                    .padding(.bottom, 14)
                }
                HStack(spacing: 16) {
                    TreemapView(rows: browser.rows)
                    StorageList(rows: browser.rows)
                        .frame(width: 300)
                }
                .padding(.horizontal, HB.Space.page)
                .padding(.bottom, 12)
                footer
            } else {
                LargestFilesList(result: result)
            }
        }
        .sheet(isPresented: $store.isReviewingCollection, onDismiss: store.closeCollection) {
            CollectionReview()
        }
    }

    private func header(mode: Binding<StorageStore.Mode>) -> some View {
        HStack(spacing: 12) {
            if let browser = store.browser {
                HStack(spacing: 2) {
                    ForEach(browser.crumbs) { crumb in
                        if crumb.depth > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(HB.Palette.textTertiary)
                        }
                        NavPill(title: crumb.title, isCurrent: crumb.depth == browser.trail.count) {
                            store.mode = .folders
                            store.leave(to: crumb.depth)
                        }
                    }
                }
                Text(ByteFormat.string(browser.current.allocatedBytes))
                    .font(HB.Typography.head)
                    .monospacedDigit()
                    .foregroundStyle(HB.Palette.text)
                if result.cancelled || result.root.incomplete {
                    Text(result.cancelled ? "Stopped, not complete" : "Some folders are not readable")
                        .font(HB.Typography.body)
                        .foregroundStyle(HB.Palette.review)
                }
            }
            Spacer()
            PillSegments(options: StorageStore.Mode.allCases.map { ($0, $0.rawValue) }, selection: mode)
            Button("Scan again", action: store.start)
                .buttonStyle(LinkButtonStyle())
                .help("Measure the home folder again")
        }
        .padding(.horizontal, HB.Space.page)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let notice = store.notice {
                Label(notice, systemImage: "exclamationmark.circle")
                    .font(HB.Typography.body)
                    .foregroundStyle(HB.Palette.review)
                    .lineLimit(1)
                Spacer()
            } else if let row = store.selectedRow {
                if let rule = store.rule(for: row) {
                    CleanupTag()
                        .help(rule.summary + " " + rule.recovery)
                }
                Text(row.path ?? row.title)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(HB.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if store.rule(for: row) != nil {
                    Button("Review in Clean", action: store.openClean)
                        .help("Clean scans this folder again and shows what it can remove")
                }
                if row.canOpen {
                    Button("Open") { store.open(row) }
                }
                if let path = row.path {
                    Button("Show in Finder") { store.reveal(path) }
                    if store.rule(for: row) == nil {
                        Button(store.isCollected(path) ? "Remove from Trash list" : "Add to Trash list") {
                            store.toggleCollect(path: path, size: row.allocatedBytes)
                        }
                        .help(store.collectRefusal(path) ?? "Pick this item to move it to the Trash after a review")
                    }
                }
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, HB.Space.page)
        .frame(height: 44)
        .overlay(alignment: .top) { Rectangle().fill(HB.Palette.border).frame(height: 1) }
    }
}

/// The opened folder as areas: one cell for each row, sized by its bytes.
private struct TreemapView: View {
    let rows: [StorageBrowser.Row]
    @Environment(StorageStore.self) private var store

    var body: some View {
        GeometryReader { proxy in
            let rects = Treemap.layout(values: rows.map { Double($0.allocatedBytes) }, in: CGRect(origin: .zero, size: proxy.size))
            ZStack(alignment: .topLeading) {
                if rows.allSatisfy({ $0.allocatedBytes == 0 }) {
                    Text("This folder is empty.")
                        .font(HB.Typography.body)
                        .foregroundStyle(HB.Palette.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ForEach(Array(zip(rows, rects)), id: \.0.id) { row, rect in
                    if rect.width >= 2, rect.height >= 2 {
                        TreemapCell(row: row, size: rect.size, isSelected: store.selectedRowID == row.id)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Folder sizes")
    }
}

private struct TreemapCell: View {
    let row: StorageBrowser.Row
    let size: CGSize
    let isSelected: Bool
    @Environment(StorageStore.self) private var store
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(HB.Radius.medium, min(size.width, size.height) / 4), style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(fill)
            if isSelected {
                shape.strokeBorder(HB.Palette.brand, lineWidth: 2)
            }
            if size.width >= 72, size.height >= 40 {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(ByteFormat.string(row.allocatedBytes))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(HB.Palette.textSecondary)
                }
                .foregroundStyle(HB.Palette.text)
                .padding(8)
            }
        }
        // A gap of one point on each side separates the cells.
        .padding(1)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .gesture(TapGesture(count: 2).onEnded { store.open(row) })
        .simultaneousGesture(TapGesture().onEnded { store.selectedRowID = row.id })
        .hbAnimation(HB.Motion.quick, value: hovering)
        .help("\(row.title) · \(ByteFormat.string(row.allocatedBytes))")
        .accessibilityElement()
        .accessibilityLabel("\(row.title), \(ByteFormat.string(row.allocatedBytes))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Folders are darker than files, so that the eye finds what can open.
    private var fill: Color {
        if hovering { return HB.Palette.active }
        return row.isDirectory ? HB.Palette.surfaceHover : HB.Palette.surface
    }
}

/// Marks an item on the Trash list.
private struct PickedTag: View {
    var body: some View {
        Image(systemName: "trash.fill")
            .font(.system(size: 9))
            .foregroundStyle(HB.Palette.review)
            .accessibilityLabel("On the Trash list")
    }
}

/// The items picked for the Trash: a count, the size and the review.
private struct CollectorBar: View {
    @Environment(StorageStore.self) private var store

    var body: some View {
        if !store.collected.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .foregroundStyle(HB.Palette.review)
                Text("\(store.collected.count) \(store.collected.count == 1 ? "item" : "items") · \(ByteFormat.string(store.collectedBytes)) picked for the Trash")
                    .font(HB.Typography.body)
                    .monospacedDigit()
                    .foregroundStyle(HB.Palette.text)
                Spacer()
                Button("Clear", action: store.clearCollected)
                    .buttonStyle(LinkButtonStyle())
                Button("Review") { store.isReviewingCollection = true }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(HB.Palette.surface, in: RoundedRectangle(cornerRadius: HB.Radius.medium, style: .continuous))
            .padding(.horizontal, HB.Space.page)
            .padding(.bottom, 12)
            .hbTransition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// The review of the picked items, then the result of the move.
private struct CollectionReview: View {
    @Environment(StorageStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let outcomes = store.collectOutcomes {
                result(outcomes)
            } else {
                review
            }
        }
        .padding(24)
        .frame(width: 560)
        .frame(minHeight: 320)
        .background(HB.Palette.background)
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Move \(ByteFormat.string(store.collectedBytes)) to the Trash?")
                    .font(HB.Typography.title)
                    .foregroundStyle(HB.Palette.text)
                Text("These items go to the Trash. You can put them back from the Trash until you empty it.")
                    .font(HB.Typography.body)
                    .foregroundStyle(HB.Palette.textSecondary)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.collected) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.isDirectory ? "folder" : "doc")
                                .foregroundStyle(HB.Palette.textTertiary)
                            Text(item.url.fileSystemPath.replacingOccurrences(of: store.root.fileSystemPath, with: "~"))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(HB.Palette.text)
                            Spacer()
                            Text(ByteFormat.string(item.size))
                                .monospacedDigit()
                                .foregroundStyle(HB.Palette.textSecondary)
                            Button("Remove", systemImage: "xmark") { store.removeCollected(item) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("Remove from the list")
                        }
                        .font(HB.Typography.body)
                        .frame(height: 34)
                        .overlay(alignment: .bottom) { Rectangle().fill(HB.Palette.border).frame(height: 1) }
                    }
                }
            }
            .frame(maxHeight: 260)
            HStack {
                Spacer()
                Button("Cancel") { store.isReviewingCollection = false }
                    .keyboardShortcut(.cancelAction)
                Button(store.isMovingCollection ? "Moving…" : "Move to Trash", action: store.moveCollected)
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.isMovingCollection || store.collected.isEmpty)
            }
        }
    }

    private func result(_ outcomes: [Collector.Outcome]) -> some View {
        let moved = outcomes.filter { if case .moved = $0.status { true } else { false } }
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Moved \(moved.count) to the Trash · \(ByteFormat.string(moved.reduce(0) { $0 + $1.item.size }))", systemImage: "checkmark.circle.fill")
                    .font(HB.Typography.title)
                    .foregroundStyle(HB.Palette.text)
                Text("Empty the Trash in Finder to free the space. To put an item back, use Put Back in the Trash.")
                    .font(HB.Typography.body)
                    .foregroundStyle(HB.Palette.textSecondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(outcomes, id: \.item) { outcome in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            switch outcome.status {
                            case .moved:
                                Image(systemName: "checkmark").foregroundStyle(HB.Palette.safe)
                                Text(outcome.item.url.lastPathComponent).foregroundStyle(HB.Palette.text)
                            case .skipped(let reason), .failed(let reason):
                                Image(systemName: "exclamationmark.circle").foregroundStyle(HB.Palette.review)
                                Text("\(outcome.item.url.lastPathComponent): \(reason)").foregroundStyle(HB.Palette.textSecondary)
                            }
                        }
                        .font(HB.Typography.body)
                    }
                }
            }
            .frame(maxHeight: 220)
            HStack {
                Spacer()
                Button("Done", action: store.closeCollection)
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Marks a folder that a cleanup rule covers.
private struct CleanupTag: View {
    var body: some View {
        Text("Cleanable")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(HB.Palette.safe)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(HB.Palette.brand.opacity(0.14), in: Capsule())
            .accessibilityLabel("A cleanup rule covers this folder")
    }
}

/// The rows of the opened folder, largest first.
private struct StorageList: View {
    let rows: [StorageBrowser.Row]
    @Environment(StorageStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(rows) { row in
                    StorageListRow(row: row, isSelected: store.selectedRowID == row.id)
                }
            }
        }
    }
}

private struct StorageListRow: View {
    let row: StorageBrowser.Row
    let isSelected: Bool
    @Environment(StorageStore.self) private var store
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: row.path == nil ? "ellipsis" : (row.isDirectory ? "folder" : "doc"))
                    .font(.system(size: 11))
                    .foregroundStyle(HB.Palette.textTertiary)
                    .frame(width: 14)
                Text(row.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(row.note == nil ? HB.Palette.text : HB.Palette.textTertiary)
                if store.rule(for: row) != nil {
                    CleanupTag()
                }
                if let path = row.path, store.isCollected(path) {
                    PickedTag()
                }
                Spacer(minLength: 8)
                Text(row.note ?? ((row.incomplete ? "≥ " : "") + ByteFormat.string(row.allocatedBytes)))
                    .monospacedDigit()
                    .foregroundStyle(row.incomplete ? HB.Palette.review : HB.Palette.textSecondary)
                if row.canOpen {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(hovering ? HB.Palette.text : HB.Palette.textTertiary)
                }
            }
            .font(HB.Typography.body)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(HB.Palette.border)
                    Capsule().fill(isSelected ? HB.Palette.brand : HB.Palette.textTertiary)
                        .frame(width: max(row.share > 0 ? 3 : 0, proxy.size.width * row.share))
                }
            }
            .frame(height: 3)
            .padding(.leading, 22)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(background, in: RoundedRectangle(cornerRadius: HB.Radius.small, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .gesture(TapGesture(count: 2).onEnded { store.open(row) })
        .simultaneousGesture(TapGesture().onEnded { store.selectedRowID = row.id })
        .hbAnimation(HB.Motion.quick, value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected { return HB.Palette.active }
        return hovering ? HB.Palette.hover : .clear
    }
}

/// The largest files of the whole scan.
private struct LargestFilesList: View {
    let result: UsageResult
    @Environment(StorageStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(result.largest, id: \.path) { file in
                    LargestFileRow(file: file, rootPath: result.path)
                }
                if result.largest.isEmpty {
                    Text("No files.")
                        .font(HB.Typography.body)
                        .foregroundStyle(HB.Palette.textTertiary)
                        .padding(.top, 40)
                }
            }
            .frame(maxWidth: HB.Space.column)
            .padding(.horizontal, HB.Space.page)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct LargestFileRow: View {
    let file: UsageFile
    let rootPath: String
    @Environment(StorageStore.self) private var store
    @State private var hovering = false

    var body: some View {
        let relative = file.path.hasPrefix(rootPath + "/") ? String(file.path.dropFirst(rootPath.count + 1)) : file.path
        let name = URL(filePath: file.path).lastPathComponent
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .foregroundStyle(HB.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(relative)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(HB.Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 12)
            // The action shows only for the row under the pointer or the
            // keyboard focus, so that the list stays quiet.
            Button("Show in Finder") { store.reveal(file.path) }
                .buttonStyle(LinkButtonStyle())
                .opacity(hovering ? 1 : 0)
                .accessibilityHidden(!hovering)
            let picked = store.isCollected(file.path)
            Button(picked ? "Remove from Trash list" : "Add to Trash list") {
                store.toggleCollect(path: file.path, size: file.allocatedBytes)
            }
            .buttonStyle(LinkButtonStyle())
            .opacity(hovering || picked ? 1 : 0)
            .accessibilityHidden(!hovering && !picked)
            .help(store.collectRefusal(file.path) ?? "Pick this file to move it to the Trash after a review")
            Text(ByteFormat.string(file.allocatedBytes))
                .monospacedDigit()
                .fontWeight(.medium)
                .foregroundStyle(HB.Palette.text)
                .frame(minWidth: 76, alignment: .trailing)
        }
        .font(HB.Typography.body)
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(hovering ? HB.Palette.hover : .clear, in: RoundedRectangle(cornerRadius: HB.Radius.small, style: .continuous))
        .overlay(alignment: .bottom) { Rectangle().fill(HB.Palette.border).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .gesture(TapGesture(count: 2).onEnded { store.reveal(file.path) })
        .hbAnimation(HB.Motion.quick, value: hovering)
    }
}
