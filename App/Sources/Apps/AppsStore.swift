import AppKit
import HandbyteCore
import HandbyteUI
import Observation

/// Drives the Apps section: the inventory, the files of the chosen app, the
/// leftovers, and the removal.
@MainActor
@Observable
final class AppsStore {
    private(set) var browser = AppsBrowser(apps: [])
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var measured = 0
    private(set) var leftovers: [LeftoverGroup] = []
    private(set) var leftoversLoaded = false

    var selectedAppID: InstalledApp.ID? {
        didSet { if selectedAppID != oldValue { loadFiles() } }
    }
    var selectedLeftoverID: LeftoverGroup.ID?
    /// The files of the chosen app, with the user's choices.
    var files: [AppFile] = []
    private(set) var isLoadingFiles = false
    var withData = false {
        didSet { applyDataChoice() }
    }
    /// Choices of the leftover items, by path.
    var leftoverChoices: Set<String> = []

    var reviewing: Review?
    private(set) var isRemoving = false
    private(set) var result: Result?
    var error: String?

    enum Review: Equatable {
        case uninstall
        case reset
        case leftovers
    }

    struct Result: Equatable {
        let title: String
        let outcomes: [AppRemover.Outcome]
        var moved: Int64 { outcomes.reduce(0) { if case .moved = $1.status { $0 + $1.bytes } else { $0 } } }
    }

    let home: URL
    let journal: OperationsJournal
    private let runningApps = WorkspaceRunningAppsProbe()
    private var loadTask: Task<Void, Never>?

    init(home: URL, journal: OperationsJournal) {
        self.home = home
        self.journal = journal
    }

    var inventory: AppInventory { AppInventory(home: home, runningApps: runningApps) }
    var roots: [URL] { inventory.roots }

    var selectedApp: InstalledApp? {
        browser.apps.first { $0.id == selectedAppID }
    }

    var selectedLeftover: LeftoverGroup? {
        leftovers.first { $0.id == selectedLeftoverID }
    }

    func loadIfNeeded() {
        if !hasLoaded { load() }
    }

    /// Lists the apps at once, then fills in the sizes and the leftovers.
    func load() {
        loadTask?.cancel()
        isLoading = true
        let inventory = inventory
        let home = home
        loadTask = Task { [weak self] in
            let list = await Task.detached { inventory.list() }.value
            guard let self, !Task.isCancelled else { return }
            let keep = self.selectedAppID
            self.browser = AppsBrowser(apps: list)
            self.browser.filter = self.filterChoice
            self.browser.query = self.queryChoice
            self.measured = 0
            self.isLoading = false
            self.hasLoaded = true
            self.selectedAppID = list.contains { $0.id == keep } ? keep : self.browser.rows(now: .now).first?.id
            await self.measure(list)
            let names = list.map(\.name)
            let ids = list.map(\.bundleID)
            let found = await Task.detached {
                var items = AppFiles.leftovers(home: home, installed: ids, names: names, isInstalledElsewhere: AppFiles.launchServicesKnows)
                for index in items.indices {
                    items[index].size = await Self.size(of: items[index].url, isDirectory: items[index].isDirectory)
                }
                return LeftoverGroup.group(items)
            }.value
            guard !Task.isCancelled else { return }
            self.leftovers = found
            self.leftoversLoaded = true
        }
    }

    /// The filter and the search outlive a reload.
    var filterChoice: AppsBrowser.Filter = .all {
        didSet { browser.filter = filterChoice }
    }

    var queryChoice = "" {
        didSet { browser.query = queryChoice }
    }

    private func measure(_ list: [InstalledApp]) async {
        await withTaskGroup(of: (InstalledApp.ID, Int64).self) { group in
            var pending = list.makeIterator()
            func next(_ group: inout TaskGroup<(InstalledApp.ID, Int64)>) {
                guard let app = pending.next() else { return }
                group.addTask { (app.id, await Self.size(of: app.url, isDirectory: true)) }
            }
            for _ in 0..<4 { next(&group) }
            for await (id, size) in group {
                browser.setSize(size, for: id)
                measured += 1
                next(&group)
            }
        }
    }

    nonisolated private static func size(of url: URL, isDirectory: Bool) async -> Int64 {
        if !isDirectory {
            var status = stat()
            return lstat(url.fileSystemPath, &status) == 0 ? Int64(status.st_blocks) * 512 : 0
        }
        var options = UsageScanner.Options()
        options.workers = 2
        options.largestFiles = 1
        options.filesPerDirectory = 1
        return await UsageScanner().scan(url, options: options)?.root.allocatedBytes ?? 0
    }

    // MARK: Files of the chosen app

    private func loadFiles() {
        files = []
        guard let app = selectedApp else { return }
        isLoadingFiles = true
        let home = home
        let others = browser.apps.filter { $0.id != app.id }.map(\.bundleID)
        let withData = withData
        Task { [weak self] in
            let found = await Task.detached {
                var files = AppFiles.related(home: home, bundleID: app.bundleID, name: app.name, zap: app.zap, others: others, withData: withData)
                for index in files.indices {
                    files[index].size = await Self.size(of: files[index].url, isDirectory: files[index].isDirectory)
                }
                return files
            }.value
            guard let self, self.selectedAppID == app.id else { return }
            self.files = found
            self.isLoadingFiles = false
        }
    }

    private func applyDataChoice() {
        for index in files.indices where files[index].fileClass == "data" && files[index].confidence != .low {
            files[index].isSelected = withData
        }
    }

    func toggle(_ file: AppFile) {
        guard let index = files.firstIndex(where: { $0.id == file.id }) else { return }
        files[index].isSelected.toggle()
    }

    var selectedFilesBytes: Int64 {
        files.filter(\.isSelected).reduce(0) { $0 + $1.size }
    }

    func refusal(reset: Bool) -> String? {
        guard let app = selectedApp else { return nil }
        let plan = AppRemover.Plan(app: app, removesApp: !reset, files: files)
        return AppRemover().refusal(for: plan, roots: roots, runningApps: runningApps)?.description
    }

    // MARK: Removal

    func confirm() {
        guard let review = reviewing, !isRemoving else { return }
        let plan: AppRemover.Plan
        let title: String
        switch review {
        case .uninstall, .reset:
            guard let app = selectedApp else { return }
            plan = AppRemover.Plan(app: app, removesApp: review == .uninstall, files: files)
            title = app.name
        case .leftovers:
            guard let group = selectedLeftover else { return }
            let app = InstalledApp(url: home, name: group.bundleID, bundleID: group.bundleID, version: nil, source: .direct,
                                   caskToken: nil, zap: [], isSystem: false, architectures: [])
            let chosen = group.items.filter { leftoverChoices.contains($0.id) }.map {
                var file = AppFile(url: $0.url, fileClass: $0.fileClass, confidence: .high, isSelected: true, isDirectory: $0.isDirectory)
                file.size = $0.size
                return file
            }
            plan = AppRemover.Plan(app: app, removesApp: false, files: chosen)
            title = group.bundleID
        }
        isRemoving = true
        let roots = roots
        let running = runningApps
        let journal = journal
        Task { [weak self] in
            let outcome = await Task.detached { () -> Swift.Result<[AppRemover.Outcome], AppRemover.Refusal> in
                do throws(AppRemover.Refusal) {
                    return .success(try AppRemover().remove(plan, roots: roots, runningApps: running, journal: journal))
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self else { return }
            self.isRemoving = false
            switch outcome {
            case .success(let outcomes):
                self.result = Result(title: title, outcomes: outcomes)
            case .failure(let refusal):
                self.error = refusal.description
                self.reviewing = nil
            }
        }
    }

    func closeReview() {
        reviewing = nil
        if result != nil {
            result = nil
            leftoverChoices = []
            load()
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
