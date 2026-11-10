import HandbyteCore
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
        }
        // The toolbar holds the mark and the section tabs; the title would
        // repeat the name.
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 920, height: 640)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
        Settings {
            SettingsView()
                .environment(store)
        }
    }
}
