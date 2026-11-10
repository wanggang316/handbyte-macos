import AppKit
import HandbyteCore
import HandbyteUI
import SwiftUI

/// The Apps section: header, filter row, list and inspector.
struct AppsView: View {
    @Environment(AppsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            header(filter: $store.filterChoice, query: $store.queryChoice)
            if !store.hasLoaded {
                ProgressView("Reading the apps…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    if store.filterChoice == .leftovers {
                        LeftoverList()
                    } else {
                        AppList()
                    }
                    Rectangle().fill(HB.Palette.border).frame(width: 1)
                    Group {
                        if store.filterChoice == .leftovers {
                            LeftoverInspector()
                        } else {
                            AppInspector()
                        }
                    }
                    .frame(width: 320)
                }
            }
        }
        .onAppear(perform: store.loadIfNeeded)
        .sheet(item: Binding(get: { store.reviewing.map(ReviewID.init) }, set: { if $0 == nil { store.closeReview() } })) { _ in
            RemovalSheet()
        }
        .alert("Not possible now", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: {
            Text(store.error ?? "")
        }
    }

    private struct ReviewID: Identifiable {
        let review: AppsStore.Review
        var id: String { "\(review)" }
    }

    private func header(filter: Binding<AppsBrowser.Filter>, query: Binding<String>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Apps").font(HB.Typography.title).foregroundStyle(HB.Palette.text)
                Text(summary)
                    .font(HB.Typography.body)
                    .monospacedDigit()
                    .foregroundStyle(HB.Palette.textTertiary)
            }
            Spacer()
            PillSegments(options: AppsBrowser.Filter.allCases.map { ($0, $0.rawValue) }, selection: filter)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(HB.Palette.textTertiary)
                TextField("Search", text: query)
                    .textFieldStyle(.plain)
                    .frame(width: 130)
            }
            .font(HB.Typography.body)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(HB.Palette.surface, in: Capsule())
        }
        .padding(.horizontal, HB.Space.page)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(HB.Palette.border).frame(height: 1) }
    }

    private var summary: String {
        let apps = store.browser.apps
        var text = "\(apps.count) apps · \(ByteFormat.string(store.browser.totalSize))"
        if store.measured < apps.count { text += " · measuring \(store.measured) of \(apps.count)" }
        if store.leftoversLoaded { text += " · \(store.leftovers.count) leftovers" }
        return text
    }
}

// MARK: List

private struct AppList: View {
    @Environment(AppsStore.self) private var store

    var body: some View {
        let rows = store.browser.rows(now: .now)
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(rows) { app in
                    AppRow(app: app, isSelected: store.selectedAppID == app.id)
                }
                if rows.isEmpty {
                    Text(store.filterChoice == .unused ? "No app was found that was not opened for six months." : "No app matches.")
                        .font(HB.Typography.body)
                        .foregroundStyle(HB.Palette.textTertiary)
                        .padding(.top, 40)
                }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let isSelected: Bool
    @Environment(AppsStore.self) private var store
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(url: app.url, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(app.name).foregroundStyle(HB.Palette.text).lineLimit(1)
                    if app.isRunning {
                        Circle().fill(HB.Palette.brand).frame(width: 6, height: 6).help("Running")
                    }
                    if app.isSystem {
                        Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(HB.Palette.textTertiary).help("Part of macOS")
                    }
                }
                Text([app.version.map { "Version \($0)" }, app.source.rawValue].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(HB.Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(lastUsed(app))
                .font(.system(size: 12))
                .foregroundStyle(HB.Palette.textTertiary)
                .frame(width: 110, alignment: .trailing)
            Text(app.size > 0 ? ByteFormat.string(app.size) : "…")
                .monospacedDigit()
                .foregroundStyle(hovering || isSelected ? HB.Palette.text : HB.Palette.textSecondary)
                .frame(width: 80, alignment: .trailing)
        }
        .font(HB.Typography.body)
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(isSelected ? HB.Palette.active : hovering ? HB.Palette.hover : .clear,
                    in: RoundedRectangle(cornerRadius: HB.Radius.small, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { store.selectedAppID = app.id }
        .hbAnimation(HB.Motion.quick, value: hovering)
        .contextMenu {
            Button("Show in Finder") { store.reveal(app.url) }
            Button("Uninstall…") {
                store.selectedAppID = app.id
                store.reviewing = .uninstall
            }
            .disabled(app.isSystem)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

func lastUsed(_ app: InstalledApp) -> String {
    guard let date = app.lastUsed else { return "Last use unknown" }
    return "Used " + date.formatted(.relative(presentation: .named))
}

struct AppIcon: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.fileSystemPath))
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: Inspector

private struct AppInspector: View {
    @Environment(AppsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        if let app = store.selectedApp {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            AppIcon(url: app.url, size: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name).font(HB.Typography.head).foregroundStyle(HB.Palette.text)
                                Text(app.bundleID).font(.system(size: 11, design: .monospaced)).foregroundStyle(HB.Palette.textTertiary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            fact("Size", app.size > 0 ? ByteFormat.string(app.size) : "Measuring…")
                            fact("Last used", app.lastUsed.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Unknown")
                            fact("Source", app.caskToken.map { "Homebrew (\($0))" } ?? app.source.rawValue)
                            fact("Version", app.version ?? "—")
                            fact("Runs on", app.architectures.joined(separator: ", "))
                        }
                        if app.lastUsed == nil {
                            Text("Spotlight has no date of last use. Unknown is not the same as never.")
                                .font(.system(size: 11)).foregroundStyle(HB.Palette.textTertiary)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Files it keeps").hbLabel()
                                Spacer()
                                Toggle("Include data", isOn: $store.withData)
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                                    .font(.system(size: 11))
                                    .help("Also select the app's own data, such as documents and databases")
                            }
                            if store.isLoadingFiles {
                                ProgressView().controlSize(.small)
                            } else if store.files.isEmpty {
                                Text(app.isSystem ? "Apps of macOS are not offered." : "No files found in ~/Library.")
                                    .font(HB.Typography.body).foregroundStyle(HB.Palette.textTertiary)
                            }
                            ForEach(store.files) { file in
                                FileToggle(file: file)
                            }
                        }
                    }
                    .padding(18)
                }
                actionBar(app)
            }
        } else {
            Text("Choose an app").font(HB.Typography.body).foregroundStyle(HB.Palette.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(HB.Palette.textTertiary)
            Text(value).foregroundStyle(HB.Palette.text).lineLimit(1)
        }
        .font(HB.Typography.body)
    }

    private func actionBar(_ app: InstalledApp) -> some View {
        let refusal = store.refusal(reset: false)
        return VStack(alignment: .leading, spacing: 8) {
            if let refusal {
                Text(refusal).font(.system(size: 11)).foregroundStyle(HB.Palette.review).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Remove Files Only…") { store.reviewing = .reset }
                    .disabled(app.isSystem || store.files.allSatisfy { !$0.isSelected })
                    .help("Keep the app; move the selected files to the Trash")
                Spacer()
                Button("Uninstall…") { store.reviewing = .uninstall }
                    .buttonStyle(.borderedProminent)
                    .tint(HB.Palette.ink)
                    .disabled(refusal != nil)
            }
        }
        .padding(14)
        .overlay(alignment: .top) { Rectangle().fill(HB.Palette.border).frame(height: 1) }
    }
}

private struct FileToggle: View {
    let file: AppFile
    @Environment(AppsStore.self) private var store

    var body: some View {
        Button { store.toggle(file) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: file.isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(file.isSelected ? HB.Palette.brand : HB.Palette.textTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.url.lastPathComponent).foregroundStyle(HB.Palette.text).lineLimit(1).truncationMode(.middle)
                    Text("\(file.fileClass) · \(file.confidence.rawValue) match · \(file.url.deletingLastPathComponent().lastPathComponent)")
                        .font(.system(size: 10)).foregroundStyle(HB.Palette.textTertiary)
                }
                Spacer(minLength: 6)
                Text(ByteFormat.string(file.size)).monospacedDigit().foregroundStyle(HB.Palette.textSecondary)
            }
            .font(.system(size: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(file.url.fileSystemPath)
        .accessibilityLabel("\(file.url.lastPathComponent), \(file.isSelected ? "selected" : "not selected")")
    }
}

// MARK: Leftovers

private struct LeftoverList: View {
    @Environment(AppsStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                if !store.leftoversLoaded {
                    ProgressView("Looking for data of removed apps…").controlSize(.small).padding(.top, 40)
                } else if store.leftovers.isEmpty {
                    Text("No data of removed apps was found.").font(HB.Typography.body)
                        .foregroundStyle(HB.Palette.textTertiary).padding(.top, 40)
                }
                ForEach(store.leftovers) { group in
                    LeftoverRow(group: group, isSelected: store.selectedLeftoverID == group.id)
                }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LeftoverRow: View {
    let group: LeftoverGroup
    let isSelected: Bool
    @Environment(AppsStore.self) private var store
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox").foregroundStyle(HB.Palette.textTertiary).frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.bundleID).foregroundStyle(HB.Palette.text).lineLimit(1).truncationMode(.middle)
                Text(group.items.count == 1 ? "1 item" : "\(group.items.count) items")
                    .font(.system(size: 11)).foregroundStyle(HB.Palette.textTertiary)
            }
            Spacer()
            Text(ByteFormat.string(group.size)).monospacedDigit().foregroundStyle(HB.Palette.textSecondary)
        }
        .font(HB.Typography.body)
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(isSelected ? HB.Palette.active : hovering ? HB.Palette.hover : .clear,
                    in: RoundedRectangle(cornerRadius: HB.Radius.small, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            store.selectedLeftoverID = group.id
            store.leftoverChoices = []
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LeftoverInspector: View {
    @Environment(AppsStore.self) private var store

    var body: some View {
        if let group = store.selectedLeftover {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.bundleID).font(HB.Typography.head).foregroundStyle(HB.Palette.text)
                        Text("No installed app has this bundle ID. Check each item before you remove it: nothing is selected for you.")
                            .font(.system(size: 12)).foregroundStyle(HB.Palette.textSecondary)
                        ForEach(group.items) { item in
                            let chosen = store.leftoverChoices.contains(item.id)
                            Button {
                                if chosen { store.leftoverChoices.remove(item.id) } else { store.leftoverChoices.insert(item.id) }
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: chosen ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(chosen ? HB.Palette.brand : HB.Palette.textTertiary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.url.lastPathComponent).foregroundStyle(HB.Palette.text).lineLimit(1).truncationMode(.middle)
                                        Text(item.url.deletingLastPathComponent().fileSystemPath.replacingOccurrences(of: store.home.fileSystemPath, with: "~"))
                                            .font(.system(size: 10)).foregroundStyle(HB.Palette.textTertiary).lineLimit(1).truncationMode(.head)
                                    }
                                    Spacer()
                                    Text(ByteFormat.string(item.size)).monospacedDigit().foregroundStyle(HB.Palette.textSecondary)
                                }
                                .font(.system(size: 12))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu { Button("Show in Finder") { store.reveal(item.url) } }
                        }
                    }
                    .padding(18)
                }
                HStack {
                    Spacer()
                    Button("Move to Trash…") { store.reviewing = .leftovers }
                        .buttonStyle(.borderedProminent)
                        .tint(HB.Palette.ink)
                        .disabled(store.leftoverChoices.isEmpty)
                }
                .padding(14)
                .overlay(alignment: .top) { Rectangle().fill(HB.Palette.border).frame(height: 1) }
            }
        } else {
            Text("Choose a leftover").font(HB.Typography.body).foregroundStyle(HB.Palette.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: Removal

private struct RemovalSheet: View {
    @Environment(AppsStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let result = store.result {
                Label("Moved \(ByteFormat.string(result.moved)) to the Trash", systemImage: "checkmark.circle.fill")
                    .font(HB.Typography.title)
                    .foregroundStyle(HB.Palette.text)
                Text("Put items back from History or with Put Back in the Trash.")
                    .font(HB.Typography.body).foregroundStyle(HB.Palette.textSecondary)
                ForEach(result.outcomes, id: \.url) { outcome in
                    HStack(spacing: 8) {
                        switch outcome.status {
                        case .moved:
                            Image(systemName: "checkmark").foregroundStyle(HB.Palette.safe)
                            Text(outcome.url.lastPathComponent)
                        case .skipped(let reason), .failed(let reason):
                            Image(systemName: "exclamationmark.circle").foregroundStyle(HB.Palette.review)
                            Text("\(outcome.url.lastPathComponent): \(reason)")
                        }
                    }
                    .font(HB.Typography.body)
                }
                HStack { Spacer(); Button("Done", action: store.closeReview).buttonStyle(PillButtonStyle()).keyboardShortcut(.defaultAction) }
            } else {
                Text(title).font(HB.Typography.title).foregroundStyle(HB.Palette.text)
                Text("Everything listed goes to the Trash. Each item is checked again right before it moves.")
                    .font(HB.Typography.body).foregroundStyle(HB.Palette.textSecondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(lines, id: \.0) { line in
                            HStack {
                                Text(line.0).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(ByteFormat.string(line.1)).monospacedDigit().foregroundStyle(HB.Palette.textSecondary)
                            }
                            .font(HB.Typography.body)
                        }
                    }
                }
                .frame(maxHeight: 220)
                HStack {
                    Spacer()
                    Button("Cancel") { store.reviewing = nil }.keyboardShortcut(.cancelAction)
                    Button(store.isRemoving ? "Moving…" : "Move to Trash", action: store.confirm)
                        .buttonStyle(PillButtonStyle())
                        .disabled(store.isRemoving || lines.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(HB.Palette.background)
    }

    private var title: String {
        switch store.reviewing {
        case .uninstall: "Uninstall \(store.selectedApp?.name ?? "")?"
        case .reset: "Remove the files of \(store.selectedApp?.name ?? "")?"
        case .leftovers: "Move the leftovers of \(store.selectedLeftover?.bundleID ?? "")?"
        case nil: ""
        }
    }

    private var lines: [(String, Int64)] {
        switch store.reviewing {
        case .uninstall:
            guard let app = store.selectedApp else { return [] }
            return [(app.url.lastPathComponent, app.size)] + store.files.filter(\.isSelected).map { ($0.url.fileSystemPath.replacingOccurrences(of: store.home.fileSystemPath, with: "~"), $0.size) }
        case .reset:
            return store.files.filter(\.isSelected).map { ($0.url.fileSystemPath.replacingOccurrences(of: store.home.fileSystemPath, with: "~"), $0.size) }
        case .leftovers:
            return (store.selectedLeftover?.items ?? []).filter { store.leftoverChoices.contains($0.id) }
                .map { ($0.url.fileSystemPath.replacingOccurrences(of: store.home.fileSystemPath, with: "~"), $0.size) }
        case nil:
            return []
        }
    }
}
