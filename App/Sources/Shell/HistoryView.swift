import HandbyteCore
import HandbyteUI
import SwiftUI

/// Past cleanups from the operations log, newest first. A move to the Trash
/// can be put back while the item is still in the Trash.
struct HistoryView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.history.items.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.history.items) { item in
                            HistoryRow(item: item)
                        }
                    }
                    .frame(maxWidth: HB.Space.column)
                    .padding(.horizontal, HB.Space.page)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear(perform: store.reloadHistory)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("History").font(HB.Typography.title).foregroundStyle(HB.Palette.text)
            Text("\(ByteFormat.string(store.history.removedBytes)) removed · \(ByteFormat.string(store.history.movedBytes)) moved to the Trash")
                .font(HB.Typography.body)
                .monospacedDigit()
                .foregroundStyle(HB.Palette.textTertiary)
            if let error = store.historyError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(HB.Typography.body)
                    .foregroundStyle(HB.Palette.review)
            }
        }
        .frame(maxWidth: HB.Space.column, alignment: .leading)
        .padding(.horizontal, HB.Space.page)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Text("No cleanups yet").font(HB.Typography.head).foregroundStyle(HB.Palette.text)
            Text("Each item that Handbyte removes or moves to the Trash is listed here.")
                .font(HB.Typography.body)
                .foregroundStyle(HB.Palette.textSecondary)
            Button("Clean now", action: store.startSmartClean)
                .buttonStyle(LinkButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryRow: View {
    let item: HistoryList.Item
    @Environment(AppStore.self) private var store
    @State private var hovering = false

    var body: some View {
        let entry = item.entry
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(filePath: entry.path).lastPathComponent)
                    .foregroundStyle(HB.Palette.text)
                    .lineLimit(1)
                Text("\(status) · \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(HB.Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if item.canRestore {
                Button("Restore") { store.restore(item) }
                    .buttonStyle(LinkButtonStyle())
                    .opacity(hovering ? 1 : 0.6)
                    .help("Put the item back from the Trash to \(entry.path)")
            }
            Text(entry.outcome == .failed ? "—" : ByteFormat.string(entry.bytes))
                .monospacedDigit()
                .foregroundStyle(HB.Palette.textSecondary)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .font(HB.Typography.body)
        .padding(.horizontal, 8)
        .frame(height: 48)
        .background(hovering ? HB.Palette.hover : .clear, in: RoundedRectangle(cornerRadius: HB.Radius.small, style: .continuous))
        .overlay(alignment: .bottom) { Rectangle().fill(HB.Palette.border).frame(height: 1) }
        .onHover { hovering = $0 }
        .hbAnimation(HB.Motion.quick, value: hovering)
        .contextMenu {
            if item.canRestore { Button("Restore") { store.restore(item) } }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.path, forType: .string)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var status: String {
        switch item.entry.outcome {
        case .moved: item.restored ? "Moved to the Trash, put back" : "Moved to the Trash"
        case .removed: "Removed"
        case .failed: "Failed: \(item.entry.detail ?? "")"
        case .restored: "Put back"
        }
    }

    private var symbol: String {
        switch item.entry.outcome {
        case .moved: item.restored ? "arrow.uturn.backward.circle" : "trash"
        case .removed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .restored: "arrow.uturn.backward.circle"
        }
    }

    private var color: Color {
        switch item.entry.outcome {
        case .failed: HB.Palette.review
        case .removed: HB.Palette.brand
        default: HB.Palette.textTertiary
        }
    }
}
