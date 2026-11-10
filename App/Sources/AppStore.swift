import AppKit
import HandbyteCore
import HandbyteUI
import Observation

/// Progress of a cleanup run: what the cleaner reported so far.
struct CleanRun: Equatable {
    let total: Int
    let mode: AppSettings.DeletionMode
    var outcomes: [CleanOutcome] = []
    var bytesClaimed: Int64 = 0

    var completed: Int { outcomes.count }
}

/// Drives the scanner and the cleaner and holds what the views show. Safety
/// decisions come from Core: the store applies `EligibilityPolicy` to the
/// scan result and hands the user's selection to `Cleaner` unchanged.
@MainActor
@Observable
final class AppStore {
    enum Phase: Equatable {
        case idle
        case scanning(ScanMonitor)
        case reviewing(ScanResult)
        /// The review view with the confirmation sheet on top.
        case confirming(ScanResult)
        case cleaning(CleanRun)
        case report(CleanReport)
    }

    private(set) var phase: Phase = .idle
    /// The section the window shows. The cleanup flow keeps its phase when
    /// the user looks at another section.
    var section: AppSection = .overview
    /// The command palette (⌘K) is open.
    var isShowingPalette = false

    /// How the Clean section shows the cleanup: Smart Clean on one screen, or
    /// the full review list ("Choose items").
    enum CleanFlow: Equatable {
        case smart
        case choose
    }

    private(set) var cleanFlow: CleanFlow = .smart
    /// Free space before the last cleanup, for the result.
    private(set) var freeBeforeClean: Int64?
    /// The plan of the Smart Clean that runs or ran last, for its result.
    private(set) var smartPlanInFlight: SmartCleanPlan?
    /// When the scan on screen started, for the speed line.
    private(set) var scanStartedAt = Date()
    /// Capacity of the volume that holds the home folder; nil when unknown.
    private(set) var volume: VolumeUsage?
    /// The Storage section has its own store; it shares the home folder.
    let storage: StorageStore
    /// The Apps section has its own store.
    let apps: AppsStore
    private(set) var volumeName: String?
    var reviewList = ReviewList(candidates: [])
    var selection = Selection(candidates: [])

    /// Saved on every change. A file that cannot be read starts from defaults
    /// and `settingsError` tells the settings window why. A change to a policy
    /// input relabels the current result, whichever control made it.
    var settings: AppSettings {
        didSet {
            persistSettings()
            if settings.exclusions != oldValue.exclusions || settings.projectRoots != oldValue.projectRoots {
                relabel()
                updateStorageHints()
            }
        }
    }
    private(set) var settingsError: String?
    let overriddenFields: Set<LaunchOverrides.Field>

    /// Probed at launch and again at the start of every scan.
    private(set) var fullDiskAccess: FullDiskAccess.Status
    /// The probe result when the current result set was scanned.
    private(set) var scanLackedFullDiskAccess = false

    let home: URL
    let journalURL: URL
    private let settingsStore: SettingsStore
    private let environment: [String: String]

    private let scanner = DiskScanner()
    private let cleaner = Cleaner()
    private var scanTask: Task<Void, Never>?
    private var cleanTask: Task<Void, Never>?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        home = LaunchOverrides.home(environment: environment)
        self.environment = environment
        journalURL = OperationsJournal.defaultURL(home: home)
        storage = StorageStore(root: home, summaries: UsageSummaryStore(fileURL: UsageSummaryStore.defaultURL(home: home)))
        apps = AppsStore(home: home, journalURL: journalURL)
        settingsStore = SettingsStore(fileURL: SettingsStore.defaultURL(home: home))
        overriddenFields = LaunchOverrides.overridden(environment: environment)
        section = LaunchOverrides.section(environment: environment)
        fullDiskAccess = FullDiskAccess.probe(home: home)
        do {
            settings = try settingsStore.load()
        } catch {
            settings = AppSettings()
            settingsError = "Settings file could not be read, defaults are in use: \(error.localizedDescription)"
        }
        updateStorageHints()
        storage.openClean = { [weak self] in self?.openCleanFromStorage() }
        storage.journalURL = journalURL
    }

    /// AppSettings plus the launch overrides, which win when set.
    var configuration: ScanConfiguration {
        var configuration = settings.scanConfiguration(home: home)
        LaunchOverrides.apply(to: &configuration, environment: environment)
        return configuration
    }

    var deletionMode: AppSettings.DeletionMode { settings.deletionMode }

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    var isCleaning: Bool {
        if case .cleaning = phase { return true }
        return false
    }

    var isConfirming: Bool {
        get {
            if case .confirming = phase { return true }
            return false
        }
        set {
            if !newValue { dismissConfirmation() }
        }
    }

    /// Built from `configuration`, not the settings alone, so overridden
    /// project roots are protected roots as well.
    private var policy: EligibilityPolicy {
        EligibilityPolicy(context: settings.policyContext(for: configuration, runningApps: WorkspaceRunningAppsProbe()))
    }

    private func persistSettings() {
        do {
            try settingsStore.save(settings)
            settingsError = nil
        } catch {
            settingsError = "Settings could not be saved: \(error.localizedDescription)"
        }
    }

    // MARK: Overview

    /// Candidates of the scan result on screen, labelled by the policy.
    private var currentCandidates: [Candidate]? {
        switch phase {
        case .reviewing(let result), .confirming(let result): result.candidates
        case .idle, .scanning, .cleaning, .report: nil
        }
    }

    var overview: OverviewSummary {
        OverviewSummary(candidates: currentCandidates, volume: volume)
    }

    func refreshVolume() {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeNameKey,
        ]
        guard let values = try? home.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage
        else {
            volume = nil
            volumeName = nil
            return
        }
        volume = VolumeUsage(
            totalBytes: Int64(total),
            availableBytes: available,
            immediatelyAvailableBytes: values.volumeAvailableCapacity.map(Int64.init)
        )
        volumeName = values.volumeName
    }

    private func updateStorageHints() {
        let configuration = configuration
        storage.hints = CleanupHints(rules: configuration.rules, home: home, projectRoots: configuration.projectRoots)
        storage.projectRoots = configuration.projectRoots
        storage.collectPolicy = CollectPolicy(home: home, exclusions: settings.exclusions.filter { $0.hasPrefix("/") })
    }

    /// From a folder of Storage that a rule covers: show Clean, and scan
    /// when there is no result yet.
    func openCleanFromStorage() {
        section = .clean
        if phase == .idle { startScan() }
    }

    /// The main action of the Overview: scan, and show the scan.
    func scanFromOverview() {
        cleanFlow = .smart
        section = .clean
        startScan()
    }

    // MARK: Full Disk Access

    func probeFullDiskAccess() {
        fullDiskAccess = FullDiskAccess.probe(home: home)
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(FullDiskAccess.settingsURL)
    }

    // MARK: Scan

    func startScan() {
        guard scanTask == nil else { return }
        probeFullDiskAccess()
        scanLackedFullDiskAccess = fullDiskAccess == .denied
        scanStartedAt = Date()
        phase = .scanning(ScanMonitor(rules: configuration.rules))

        // Events arrive on scanner threads; the stream keeps their order and
        // the consumer applies them on the main actor. Only `scanTask` is
        // cancelled: `collect` then returns the partial result.
        let (events, continuation) = AsyncStream.makeStream(of: ScanEvent.self)
        let consumer = Task { [weak self] in
            for await event in events {
                self?.applyScanEvent(event)
            }
        }
        let configuration = configuration
        let scanner = scanner
        scanTask = Task { [weak self] in
            let result = await scanner.collect(configuration) { continuation.yield($0) }
            continuation.finish()
            await consumer.value
            self?.finishScan(result)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    private func applyScanEvent(_ event: ScanEvent) {
        guard case .scanning(var monitor) = phase else { return }
        monitor.apply(event)
        phase = .scanning(monitor)
    }

    /// Labels with the policy as it is now, so an exclusion added during the
    /// scan applies to this result.
    private func finishScan(_ result: ScanResult) {
        scanTask = nil
        let labelled = labelled(result)
        reviewList = ReviewList(candidates: labelled.candidates)
        selection = Selection(candidates: labelled.candidates)
        // "Choose items" starts with the safe items selected.
        if cleanFlow == .choose { selection.selectAllSafe() }
        phase = .reviewing(labelled)
    }

    private func labelled(_ result: ScanResult) -> ScanResult {
        ScanResult(
            candidates: policy.apply(to: result.candidates),
            categories: result.categories,
            bytesSeen: result.bytesSeen,
            filesSeen: result.filesSeen,
            cancelled: result.cancelled
        )
    }

    // MARK: Exclusions

    /// "Never clean this": the path joins the exclusion list and the policy
    /// runs again on the current result, so the row turns blocked at once.
    func exclude(_ candidate: Candidate) {
        settings.exclude(candidate)
    }

    func removeExclusion(_ entry: String) {
        settings.removeExclusion(entry)
    }

    func isExcluded(_ candidate: Candidate) -> Bool {
        settings.excludes(candidate)
    }

    private func relabel() {
        guard case .reviewing(let result) = phase else { return }
        let relabelled = labelled(result)
        var list = ReviewList(candidates: relabelled.candidates)
        list.query = reviewList.query
        list.sortOrder = reviewList.sortOrder
        reviewList = list
        selection = Selection(candidates: relabelled.candidates, keeping: selection)
        phase = .reviewing(relabelled)
    }

    // MARK: Confirm and clean

    func requestConfirmation() {
        guard case .reviewing(let result) = phase, !selection.selectedIDs.isEmpty else { return }
        phase = .confirming(result)
    }

    func dismissConfirmation() {
        guard case .confirming(let result) = phase else { return }
        phase = .reviewing(result)
    }

    /// `acknowledged` is the distinct confirmation for permanent deletion.
    /// Without it, permanent deletion is refused and nothing happens.
    func confirmClean(acknowledged: Bool = false) {
        guard case .confirming = phase, cleanTask == nil,
              let actions = CleanConfirmation.actions(for: deletionMode, acknowledged: acknowledged)
        else { return }
        run(selection.selectedCandidates, mode: deletionMode, actions: actions)
    }

    // MARK: Smart Clean

    /// The main action of the Overview: Smart Clean. It scans unless a result
    /// is on screen, then waits for one confirmation on the same screen.
    func startSmartClean() {
        cleanFlow = .smart
        section = .clean
        switch phase {
        case .reviewing, .confirming, .scanning:
            break
        case .idle, .cleaning, .report:
            if !isCleaning { startScan() }
        }
    }

    /// What Smart Clean takes from the result on screen.
    var smartPlan: SmartCleanPlan? {
        currentCandidates.map { SmartCleanPlan(candidates: $0) }
    }

    /// Cleans the safe items. A permanent mode in the settings needs its own
    /// acknowledgement, so Smart Clean then removes by data class.
    func cleanSmart() {
        guard case .reviewing = phase, cleanTask == nil, let plan = smartPlan, !plan.selection.isEmpty else { return }
        let mode: AppSettings.DeletionMode = deletionMode == .trash ? .trash : .byData
        guard let actions = CleanConfirmation.actions(for: mode, acknowledged: false) else { return }
        smartPlanInFlight = plan
        run(plan.selection, mode: mode, actions: actions)
    }

    /// Opens the full list with the safe items selected.
    func chooseItems() {
        cleanFlow = .choose
        section = .clean
        if case .reviewing = phase {
            selection.clear()
            selection.selectAllSafe()
        } else if phase == .idle {
            startScan()
        }
    }

    private func run(_ targets: [Candidate], mode: AppSettings.DeletionMode, actions: @escaping @Sendable (Candidate) -> CleanAction) {
        refreshVolume()
        freeBeforeClean = volume?.availableBytes
        phase = .cleaning(CleanRun(total: targets.count, mode: mode))

        let (updates, continuation) = AsyncStream.makeStream(of: CleanProgress.self)
        let consumer = Task { [weak self] in
            for await progress in updates {
                self?.applyCleanProgress(progress)
            }
        }
        let cleaner = cleaner
        let policy = policy
        let journal = OperationsJournal(fileURL: journalURL)
        cleanTask = Task { [weak self] in
            let outcomes = await cleaner.clean(targets, actions: actions, policy: policy, journal: journal) {
                continuation.yield($0)
            }
            continuation.finish()
            await consumer.value
            self?.finishClean(outcomes)
        }
    }

    func cancelClean() {
        cleanTask?.cancel()
    }

    private func applyCleanProgress(_ progress: CleanProgress) {
        guard case .cleaning(var run) = phase else { return }
        run.outcomes.append(progress.latest)
        run.bytesClaimed = progress.bytesClaimed
        phase = .cleaning(run)
    }

    private func finishClean(_ outcomes: [CleanOutcome]) {
        cleanTask = nil
        refreshVolume()
        phase = .report(CleanReport(outcomes: outcomes))
    }

    // MARK: History

    private(set) var history = HistoryList(entries: [])
    private(set) var historyError: String?

    func reloadHistory() {
        do {
            history = HistoryList(entries: try OperationsJournal(fileURL: journalURL).entries())
            historyError = nil
        } catch {
            historyError = "The operations log could not be read: \(error.localizedDescription)"
        }
    }

    func restore(_ item: HistoryList.Item) {
        let journal = OperationsJournal(fileURL: journalURL)
        do {
            try Restorer().restore(item.entry, journal: journal)
            historyError = nil
        } catch {
            historyError = "\(URL(filePath: item.entry.path).lastPathComponent): \(error.description)"
        }
        reloadHistory()
    }

    // MARK: Finder

    func reveal(_ candidate: Candidate) {
        NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
    }

    /// The log exists only after the first applied action; fall back to its folder.
    var canShowJournal: Bool {
        FileManager.default.fileExists(atPath: journalURL.path(percentEncoded: false))
            || FileManager.default.fileExists(atPath: journalURL.deletingLastPathComponent().path(percentEncoded: false))
    }

    func showJournal() {
        if FileManager.default.fileExists(atPath: journalURL.path(percentEncoded: false)) {
            NSWorkspace.shared.activateFileViewerSelecting([journalURL])
        } else {
            NSWorkspace.shared.open(journalURL.deletingLastPathComponent())
        }
    }
}
