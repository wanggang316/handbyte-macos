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
            if store.mode == .folders, let browser = store.browser {
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
                        NavPill(title: crumb.title, isCurrent: crumb.depth == browser.trail.count, isPlanned: false) {
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
            Picker("View", selection: mode) {
                ForEach(StorageStore.Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button("Scan again", systemImage: "arrow.clockwise", action: store.start)
                .labelStyle(.iconOnly)
                .help("Scan again")
        }
        .padding(.horizontal, HB.Space.page)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let row = store.selectedRow {
                Text(row.path ?? row.title)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(HB.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if row.canOpen {
                    Button("Open") { store.open(row) }
                }
                if let path = row.path {
                    Button("Show in Finder") { store.reveal(path) }
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
        .animation(HB.Motion.quick, value: hovering)
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
        .animation(HB.Motion.quick, value: hovering)
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
        .animation(HB.Motion.quick, value: hovering)
    }
}
