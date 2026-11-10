import HandbyteUI
import SwiftUI

/// ⌘K: find a section or an action by typing, run it with Return.
struct CommandPaletteView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var cursor = 0
    @FocusState private var focused: Bool

    var body: some View {
        let commands = PaletteCommand.matching(query)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(HB.Palette.textTertiary).accessibilityHidden(true)
                TextField("Type a command", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($focused)
                    .onSubmit { run(commands) }
            }
            .padding(14)
            Rectangle().fill(HB.Palette.border).frame(height: 1)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                        PaletteRow(command: command, isCurrent: index == cursor) {
                            cursor = index
                            run(commands)
                        }
                    }
                    if commands.isEmpty {
                        Text("No command matches.").font(HB.Typography.body).foregroundStyle(HB.Palette.textTertiary).padding(20)
                    }
                }
                .padding(6)
            }
            .frame(height: 300)
        }
        .frame(width: 480)
        .background(HB.Palette.background)
        .onAppear { focused = true }
        .onChange(of: query) { cursor = 0 }
        .onKeyPress(.downArrow) {
            cursor = min(cursor + 1, max(0, commands.count - 1))
            return .handled
        }
        .onKeyPress(.upArrow) {
            cursor = max(cursor - 1, 0)
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    private func run(_ commands: [PaletteCommand]) {
        guard cursor < commands.count else { return }
        let action = commands[cursor].action
        dismiss()
        switch action {
        case .show(let section): store.section = section
        case .smartClean: store.startSmartClean()
        case .chooseItems: store.chooseItems()
        case .scanStorage:
            store.section = .storage
            store.storage.start()
        case .leftovers:
            store.section = .apps
            store.apps.filterChoice = .leftovers
        case .settings: openSettings()
        case .operationsLog: store.showJournal()
        }
    }
}

private struct PaletteRow: View {
    let command: PaletteCommand
    let isCurrent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(command.title).foregroundStyle(HB.Palette.text)
                Spacer()
                if isCurrent {
                    Image(systemName: "return").font(.system(size: 11)).foregroundStyle(HB.Palette.textTertiary).accessibilityHidden(true)
                }
            }
            .font(HB.Typography.body)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(isCurrent ? HB.Palette.active : hovering ? HB.Palette.hover : .clear,
                        in: RoundedRectangle(cornerRadius: HB.Radius.small, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
