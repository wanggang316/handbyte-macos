import HandbyteCore
import HandbyteUI
import Sparkle
import SwiftUI

@main
struct HandbyteApp: App {
    // Debug builds are ad-hoc signed and never match the appcast, so the
    // updater only starts in Release builds.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: Self.startsUpdater,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    @State private var store = AppStore()

    private static var startsUpdater: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(store.storage)
                .environment(store.apps)
        }
        // The toolbar holds the mark and the section tabs; the title would
        // repeat the name.
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 920, height: 640)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(after: .sidebar) {
                Button("Command Palette…") { store.isShowingPalette = true }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.title) { store.section = section }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
                Divider()
                Button("Clean Now") { store.startSmartClean() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        Settings {
            SettingsView()
                .environment(store)
        }
    }
}
