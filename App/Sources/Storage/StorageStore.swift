import AppKit
import HandbyteCore
import HandbyteUI
import Observation

/// Drives the storage scan and holds what the Storage section shows. The
/// section is read-only: it measures, opens folders and shows items in Finder.
@MainActor
@Observable
final class StorageStore {
    enum Phase: Equatable {
        case idle
        case scanning(UsageProgress)
        case ready(UsageResult)
        /// The folder could not be read at all.
        case failed
    }

    enum Mode: String, CaseIterable, Identifiable {
        case folders = "Folders"
        case largestFiles = "Largest files"
        var id: String { rawValue }
    }

    private(set) var phase: Phase = .idle
    /// The last complete scan of the root, from this run or an earlier one.
    private(set) var lastSummary: UsageSummary?
    /// Categories of the scan on screen, largest first.
    private(set) var categories: [CategoryTotal] = []
    private(set) var browser: StorageBrowser?
    private(set) var startedAt = Date()
    var mode: Mode = .folders
    /// The highlighted row of the opened folder.
    var selectedRowID: StorageBrowser.Row.ID?

    let root: URL
    /// Which folders a cleanup rule covers. The app store keeps it in step
    /// with the settings.
    var hints: CleanupHints?
    /// Opens Clean. Set by the app store.
    var openClean: () -> Void = {}
    private let scanner = UsageScanner()
    private var task: Task<Void, Never>?

    /// The project roots belong to the Developer category. The app store
    /// keeps them in step with the settings.
    var projectRoots: [String] = []
    private let summaries: UsageSummaryStore

    init(root: URL, summaries: UsageSummaryStore) {
        self.root = root
        self.summaries = summaries
        lastSummary = summaries.load(path: Self.physical(root))
    }

    private static func physical(_ url: URL) -> String {
        UsageScanner.physicalPath(url) ?? url.path(percentEncoded: false)
    }

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    var selectedRow: StorageBrowser.Row? {
        browser?.rows.first { $0.id == selectedRowID }
    }

    /// Starts a scan when the section opens for the first time.
    func startIfNeeded() {
        if phase == .idle { start() }
    }

    func start() {
        guard task == nil else { return }
        startedAt = Date()
        browser = nil
        selectedRowID = nil
        mode = .folders
        phase = .scanning(UsageProgress(currentPath: root.path(percentEncoded: false)))
        let root = root
        let scanner = scanner
        task = Task { [weak self] in
            // Snapshots arrive on scanner threads about ten times each second.
            let result = await scanner.scan(root) { progress in
                Task { @MainActor in self?.apply(progress) }
            }
            self?.finish(result)
        }
    }

    /// Stops the scan. The result holds what was measured until then.
    func stop() {
        task?.cancel()
    }

    private func apply(_ progress: UsageProgress) {
        guard isScanning else { return }
        phase = .scanning(progress)
    }

    private func finish(_ result: UsageResult?) {
        task = nil
        guard let result else {
            phase = .failed
            return
        }
        browser = StorageBrowser(rootPath: result.path, root: result.root)
        selectedRowID = browser?.rows.first?.id
        categories = UsageCategories.totals(
            of: result,
            paths: StorageCatalog.shared.paths(home: URL(filePath: Self.physical(root)), projectRoots: projectRoots)
        )
        if !result.cancelled {
            let summary = UsageSummary(result: result, categories: categories, at: Date())
            lastSummary = summary
            // A failed write only costs the instant result of the next run.
            try? summaries.save(summary)
        }
        phase = .ready(result)
    }

    // MARK: Navigation

    func open(_ row: StorageBrowser.Row) {
        guard row.canOpen else { return }
        browser?.open(row)
        selectedRowID = browser?.rows.first?.id
    }

    func leave(to depth: Int) {
        guard let browser, depth < browser.trail.count else { return }
        let opened = browser.trail[depth]
        self.browser?.leave(to: depth)
        // Keep the place: highlight the folder that was open.
        selectedRowID = opened
    }

    /// The cleanup rule that covers a row, if any.
    func rule(for row: StorageBrowser.Row) -> Rule? {
        row.path.flatMap { hints?.rule(for: $0) }
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
    }
}
