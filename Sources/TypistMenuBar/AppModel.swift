import AppKit
import Combine
import Foundation
import TypistCore

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case statusIcon
    case keyboard
    case analytics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .statusIcon: return "Status Icon"
        case .keyboard: return "Keyboard"
        case .analytics: return "Analytics"
        }
    }
}

enum StatusIconStyle: String, CaseIterable, Identifiable {
    case dynamic
    case minimal
    case glyph

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dynamic: return "Dynamic (Default)"
        case .minimal: return "Minimal"
        case .glyph: return "Glyph"
        }
    }
}

enum StatusTextMetric: String, CaseIterable, Identifiable {
    case keystrokes
    case words

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keystrokes: return "Keystrokes"
        case .words: return "Words"
        }
    }
}

struct StatusItemState {
    let text: String
    let iconStyle: StatusIconStyle
    let monochrome: Bool
}

@MainActor
final class AppModel: ObservableObject {
    private enum DefaultsKey {
        static let didAttemptPermissionPrompt = "typist.didAttemptPermissionPrompt"
        static let selectedTimeframe = "typist.selectedTimeframe"
        static let statusIconStyle = "typist.statusIconStyle"
        static let showStatusTextCount = "typist.showStatusTextCount"
        static let statusTextMetric = "typist.statusTextMetric"
        static let statusIconMonochrome = "typist.statusIconMonochrome"
        static let showHeatmapInPopover = "typist.showHeatmapInPopover"
        static let showDiagnosticsInPopover = "typist.showDiagnosticsInPopover"
        static let hasShownUnsignedInstallNotice = "typist.hasShownUnsignedInstallNotice"
        static let didDismissUnsignedInstallNotice = "typist.didDismissUnsignedInstallNotice"
        static let autoCheckUpdates = "typist.autoCheckUpdates"
        static let updateCheckIntervalHours = "typist.updateCheckIntervalHours"
        static let lastUpdateCheckAt = "typist.lastUpdateCheckAt"
        static let lastPromptedUpdateTag = "typist.lastPromptedUpdateTag"
    }

    @Published var selectedTimeframe: Timeframe = .h12 {
        didSet {
            defaults.set(selectedTimeframe.rawValue, forKey: DefaultsKey.selectedTimeframe)
            selectedHeatmapKeyCode = nil
            let timeframe = selectedTimeframe
            Task { await refreshSelectedTimeframe(for: timeframe) }
        }
    }

    @Published var selectedSettingsTab: SettingsTab = .general
    @Published var selectedHeatmapKeyCode: Int?

    @Published private(set) var snapshot: StatsSnapshot
    @Published private(set) var permissionGranted = false
    @Published private(set) var captureRunning = false
    @Published private(set) var statusMessage = "Checking permissions…"
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchErrorMessage: String?
    @Published private(set) var debugSummary = "Diagnostics loading…"
    @Published private(set) var debugLines: [String] = []
    @Published private(set) var showUnsignedInstallNotice = false
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var updateStatusText = "Updates have not been checked yet."
    @Published private(set) var latestVersionLabel: String?
    @Published private(set) var lastUpdateCheckDate: Date?

    @Published var statusIconStyle: StatusIconStyle {
        didSet {
            defaults.set(statusIconStyle.rawValue, forKey: DefaultsKey.statusIconStyle)
            publishStatusItemState()
        }
    }

    @Published var showStatusTextCount: Bool {
        didSet {
            defaults.set(showStatusTextCount, forKey: DefaultsKey.showStatusTextCount)
            publishStatusItemState()
        }
    }

    @Published var statusTextMetric: StatusTextMetric {
        didSet {
            defaults.set(statusTextMetric.rawValue, forKey: DefaultsKey.statusTextMetric)
            publishStatusItemState()
        }
    }

    @Published var statusIconMonochrome: Bool {
        didSet {
            defaults.set(statusIconMonochrome, forKey: DefaultsKey.statusIconMonochrome)
            publishStatusItemState()
        }
    }

    @Published var showHeatmapInPopover: Bool {
        didSet {
            defaults.set(showHeatmapInPopover, forKey: DefaultsKey.showHeatmapInPopover)
        }
    }

    @Published var showDiagnosticsInPopover: Bool {
        didSet {
            defaults.set(showDiagnosticsInPopover, forKey: DefaultsKey.showDiagnosticsInPopover)
        }
    }

    @Published var autoCheckUpdates: Bool {
        didSet {
            defaults.set(autoCheckUpdates, forKey: DefaultsKey.autoCheckUpdates)
        }
    }

    var statusItemStateHandler: ((StatusItemState) -> Void)?
    var openSettingsHandler: (() -> Void)?

    private let metricsEngine: MetricsEngine
    private let defaults: UserDefaults
    private let store: StatsResetting
    private let captureService: KeyboardCaptureProviding
    private let launchAtLoginManager: LaunchAtLoginManager
    private let updateService: any UpdateChecking
    private let diagnostics = AppDiagnostics.shared

    private var captureTask: Task<Void, Never>?
    private var popoverRefreshTask: Task<Void, Never>?
    private var statusRefreshTask: Task<Void, Never>?
    private var snapshotRefreshCount = 0
    private var latestStatusKeystrokes = 0
    private var latestStatusWords = 0
    private var latestReleaseURL: URL?
    private let autoUpdateCheckIntervalHours: Double

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    init(
        metricsEngine: MetricsEngine,
        store: StatsResetting,
        captureService: KeyboardCaptureProviding,
        launchAtLoginManager: LaunchAtLoginManager,
        updateService: any UpdateChecking,
        defaults: UserDefaults = AppStorage.defaults
    ) {
        self.defaults = defaults
        let initialTimeframe = Timeframe(
            rawValue: defaults.string(forKey: DefaultsKey.selectedTimeframe) ?? ""
        ) ?? .h12

        self.metricsEngine = metricsEngine
        self.store = store
        self.captureService = captureService
        self.launchAtLoginManager = launchAtLoginManager
        self.updateService = updateService
        self.selectedTimeframe = initialTimeframe
        self.snapshot = .empty(timeframe: initialTimeframe)
        self.launchAtLoginEnabled = launchAtLoginManager.isEnabled

        self.statusIconStyle = StatusIconStyle(rawValue: defaults.string(forKey: DefaultsKey.statusIconStyle) ?? "") ?? .dynamic
        self.showStatusTextCount = Self.boolDefault(forKey: DefaultsKey.showStatusTextCount, defaults: defaults, defaultValue: true)
        self.statusTextMetric = StatusTextMetric(rawValue: defaults.string(forKey: DefaultsKey.statusTextMetric) ?? "") ?? .keystrokes
        self.statusIconMonochrome = Self.boolDefault(forKey: DefaultsKey.statusIconMonochrome, defaults: defaults, defaultValue: true)
        self.showHeatmapInPopover = Self.boolDefault(forKey: DefaultsKey.showHeatmapInPopover, defaults: defaults, defaultValue: true)
        self.showDiagnosticsInPopover = Self.boolDefault(forKey: DefaultsKey.showDiagnosticsInPopover, defaults: defaults, defaultValue: true)
        self.autoCheckUpdates = Self.boolDefault(forKey: DefaultsKey.autoCheckUpdates, defaults: defaults, defaultValue: true)
        self.showUnsignedInstallNotice = Self.shouldDisplayUnsignedInstallNotice(defaults: defaults)
        self.lastUpdateCheckDate = defaults.object(forKey: DefaultsKey.lastUpdateCheckAt) as? Date
        self.autoUpdateCheckIntervalHours = Self.doubleDefault(
            forKey: DefaultsKey.updateCheckIntervalHours,
            defaults: defaults,
            defaultValue: 24
        )

        if showUnsignedInstallNotice {
            defaults.set(true, forKey: DefaultsKey.hasShownUnsignedInstallNotice)
        }

        if let lastUpdateCheckDate {
            self.updateStatusText = "Last checked \(Self.relativeDateFormatter.localizedString(for: lastUpdateCheckDate, relativeTo: Date()))."
        }
    }

    func start() async {
        diagnostics.mark("AppModel start")
        permissionGranted = PermissionsService.hasInputMonitoringPermission()

        if permissionGranted {
            statusMessage = "Input monitoring enabled"
            await startCapture()
        } else {
            statusMessage = "Input monitoring permission required"
            await requestPermissionIfFirstLaunch()
        }

        await refreshSelectedTimeframe()
        await refreshStatusItemCounts()
        await refreshDiagnostics()
        startStatusRefreshLoop()

        if shouldRunAutomaticUpdateCheck(now: Date()) {
            Task { [weak self] in
                await self?.checkForUpdates(userInitiated: false)
            }
        }
    }

    func shutdown() async {
        diagnostics.mark("AppModel shutdown")
        captureTask?.cancel()
        captureTask = nil

        popoverRefreshTask?.cancel()
        popoverRefreshTask = nil

        statusRefreshTask?.cancel()
        statusRefreshTask = nil

        captureService.stop()
        await metricsEngine.stop()
        await refreshDiagnostics()
    }

    func requestPermission() async {
        _ = PermissionsService.requestInputMonitoringPermission()
        permissionGranted = PermissionsService.hasInputMonitoringPermission()

        if permissionGranted {
            statusMessage = "Input monitoring enabled"
            await startCapture()
        } else {
            statusMessage = "Permission not granted. Open System Settings > Privacy & Security > Input Monitoring."
        }
        await refreshDiagnostics()
    }

    func openInputMonitoringSettings() {
        PermissionsService.openInputMonitoringSettings()
    }

    func setPopoverVisible(_ visible: Bool) {
        if visible {
            diagnostics.mark("Popover opened")
            popoverRefreshTask?.cancel()
            popoverRefreshTask = Task {
                await refreshPermissionAndCaptureState()
                await refreshSelectedTimeframe()
                await refreshStatusItemCounts()
                await refreshDiagnostics()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    await refreshPermissionAndCaptureState()
                    await refreshSelectedTimeframe()
                    await refreshStatusItemCounts()
                    await refreshDiagnostics()
                }
            }
        } else {
            diagnostics.mark("Popover closed")
            popoverRefreshTask?.cancel()
            popoverRefreshTask = nil
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginManager.setEnabled(enabled)
        launchAtLoginEnabled = launchAtLoginManager.isEnabled
        launchErrorMessage = launchAtLoginManager.lastError
    }

    func resetStats() async {
        do {
            diagnostics.recordReset()
            if captureTask != nil {
                captureTask?.cancel()
                captureTask = nil
                captureService.stop()
                captureRunning = false
            }

            await metricsEngine.resetInMemoryState()
            try await store.resetAllData()

            if permissionGranted {
                await startCapture()
            }

            await refreshSelectedTimeframe()
            await refreshStatusItemCounts()
            await refreshDiagnostics()
        } catch {
            statusMessage = "Failed to reset stats: \(error.localizedDescription)"
            diagnostics.mark("Reset stats failed: \(error.localizedDescription)")
        }
    }

    func openSettings(tab: SettingsTab = .general) {
        selectedSettingsTab = tab
        openSettingsHandler?()
    }

    func copyDiagnosticsToClipboard() {
        Task { @MainActor in
            let report = await diagnosticsReport()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(report, forType: .string)
            diagnostics.mark("Copied diagnostics report to clipboard")
            await refreshDiagnostics()
        }
    }

    func copyUnsignedInstallCommandsToClipboard() {
        let commands = Self.unsignedInstallCommands()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(commands, forType: .string)
        diagnostics.mark("Copied unsigned install command to clipboard")
    }

    func dismissUnsignedInstallNotice() {
        guard showUnsignedInstallNotice else { return }
        defaults.set(true, forKey: DefaultsKey.didDismissUnsignedInstallNotice)
        showUnsignedInstallNotice = false
    }

    func checkForUpdates(userInitiated: Bool) async {
        guard !isCheckingForUpdates else { return }

        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        diagnostics.mark("Checking for updates (userInitiated=\(userInitiated))")
        let result = await updateService.checkForUpdates(channel: .beta)

        switch result {
        case let .upToDate(current, checkedAt):
            latestVersionLabel = current.description
            latestReleaseURL = nil
            recordUpdateCheckDate(checkedAt)
            updateStatusText = "Up to date (\(current.description)). Last checked \(Self.relativeDateFormatter.localizedString(for: checkedAt, relativeTo: Date()))."
            diagnostics.mark("No update available (current=\(current.description))")
            if userInitiated {
                showUpToDateAlert(current: current)
            }

        case let .updateAvailable(current, latest, checkedAt):
            latestVersionLabel = latest.version.description
            latestReleaseURL = latest.htmlURL
            recordUpdateCheckDate(checkedAt)
            updateStatusText = "Update available: \(latest.version.description) (current \(current.description))."
            diagnostics.mark("Update available (current=\(current.description), latest=\(latest.version.description))")
            let shouldShowPrompt = userInitiated || shouldPromptForUpdate(tag: latest.tag)
            if shouldShowPrompt {
                markPromptedUpdateTag(latest.tag)
                showUpdateAvailableAlert(current: current, latest: latest)
            }

        case let .unavailable(reason, checkedAt):
            recordUpdateCheckDate(checkedAt)
            updateStatusText = reason.userMessage
            diagnostics.mark("Update check unavailable: \(reason.userMessage)")
            if userInitiated {
                showUpdateErrorAlert(reason: reason)
            }
        }
    }

    func openLatestReleasePage() {
        NSWorkspace.shared.open(latestReleaseURL ?? updateService.releasesPageURL)
    }

    private func startCapture() async {
        guard captureTask == nil else { return }

        diagnostics.recordCaptureStartAttempt()
        await metricsEngine.start()

        do {
            try captureService.start()
            captureRunning = true
            diagnostics.recordCaptureStartSuccess()
        } catch {
            captureRunning = false
            statusMessage = "Capture start failed: \(error.localizedDescription)"
            diagnostics.recordCaptureStartFailure(error)
            return
        }

        captureTask = Task(priority: .high) { [diagnostics, metricsEngine, captureService] in
            for await event in captureService.events {
                diagnostics.recordAppReceivedEvent(event)
                await metricsEngine.ingest(event)
            }
        }
    }

    private func refreshSelectedTimeframe() async {
        await refreshSelectedTimeframe(for: selectedTimeframe)
    }

    private func refreshSelectedTimeframe(for timeframe: Timeframe) async {
        do {
            let latest = try await metricsEngine.snapshot(for: timeframe, now: Date())
            guard timeframe == selectedTimeframe else { return }
            snapshot = latest
            snapshotRefreshCount += 1
            if snapshotRefreshCount <= 3 || snapshotRefreshCount % 20 == 0 {
                diagnostics.mark("Snapshot refresh: timeframe=\(timeframe.rawValue) keys=\(latest.totalKeystrokes) words=\(latest.totalWords)")
            }
        } catch {
            guard timeframe == selectedTimeframe else { return }
            statusMessage = "Failed to load stats: \(error.localizedDescription)"
            diagnostics.mark("Snapshot refresh failed: \(error.localizedDescription)")
        }
    }

    private func startStatusRefreshLoop() {
        statusRefreshTask?.cancel()
        statusRefreshTask = Task {
            while !Task.isCancelled {
                await refreshStatusItemCounts()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func refreshStatusItemCounts() async {
        do {
            let statusSnapshot = try await metricsEngine.snapshot(for: .h24, now: Date())
            latestStatusKeystrokes = statusSnapshot.totalKeystrokes
            latestStatusWords = statusSnapshot.totalWords
            publishStatusItemState()
        } catch {
            publishStatusItemState(overrideText: showStatusTextCount ? "--" : "")
            diagnostics.mark("Status item refresh failed")
        }
    }

    private func publishStatusItemState(overrideText: String? = nil) {
        let metricValue: Int
        switch statusTextMetric {
        case .keystrokes:
            metricValue = latestStatusKeystrokes
        case .words:
            metricValue = latestStatusWords
        }

        let baseText = Self.countFormatter.string(from: NSNumber(value: metricValue)) ?? "\(metricValue)"
        let text = overrideText ?? (showStatusTextCount ? baseText : "")

        statusItemStateHandler?(
            StatusItemState(
                text: text,
                iconStyle: statusIconStyle,
                monochrome: statusIconMonochrome
            )
        )
    }

    private func requestPermissionIfFirstLaunch() async {
        guard !defaults.bool(forKey: DefaultsKey.didAttemptPermissionPrompt) else { return }
        defaults.set(true, forKey: DefaultsKey.didAttemptPermissionPrompt)

        _ = PermissionsService.requestInputMonitoringPermission()
        await refreshPermissionAndCaptureState()

        if permissionGranted {
            statusMessage = "Input monitoring enabled"
        } else {
            statusMessage = "Permission required. Use Enable Input Monitoring or Open Settings."
        }
    }

    private func refreshPermissionAndCaptureState() async {
        let hasPermission = PermissionsService.hasInputMonitoringPermission()
        permissionGranted = hasPermission

        if hasPermission {
            if !captureRunning {
                await startCapture()
            }
            if captureRunning {
                statusMessage = "Input monitoring enabled"
            }
        } else {
            if captureRunning {
                statusMessage = "Capture running. If counts stop, re-enable Input Monitoring in System Settings."
            } else {
                statusMessage = "Input monitoring permission required"
            }
        }
        await refreshDiagnostics()
    }

    private func refreshDiagnostics() async {
        let appSnapshot = diagnostics.snapshot()
        let engineDiagnostics = await metricsEngine.diagnostics()

        debugSummary =
            "perm=\(permissionGranted ? "yes" : "no") cap=\(captureRunning ? "yes" : "no") " +
            "hid=\(appSnapshot.hidCallbacks) yielded=\(appSnapshot.hidYieldedEvents) " +
            "app=\(appSnapshot.appReceivedEvents) engIn=\(engineDiagnostics.totalIngestedEvents) " +
            "pending=\(engineDiagnostics.pendingEvents) flushed=\(engineDiagnostics.totalFlushedEvents)"

        if let flushError = engineDiagnostics.lastFlushError, !flushError.isEmpty {
            debugSummary += " flushErr=\(flushError)"
        }

        debugLines = Array(appSnapshot.lines.suffix(6))
    }

    private func diagnosticsReport() async -> String {
        let appSnapshot = diagnostics.snapshot()
        let engineDiagnostics = await metricsEngine.diagnostics()

        let lines = [
            "=== Typist Diagnostics ===",
            "permissionGranted=\(permissionGranted)",
            "captureRunning=\(captureRunning)",
            "selectedTimeframe=\(selectedTimeframe.rawValue)",
            "snapshot.totalKeystrokes=\(snapshot.totalKeystrokes)",
            "snapshot.totalWords=\(snapshot.totalWords)",
            "--- counters ---",
            "permissionChecks=\(appSnapshot.permissionChecks)",
            "permissionRequests=\(appSnapshot.permissionRequests)",
            "permissionGrantedChecks=\(appSnapshot.permissionGrantedChecks)",
            "captureStartAttempts=\(appSnapshot.captureStartAttempts)",
            "captureStartSuccesses=\(appSnapshot.captureStartSuccesses)",
            "captureStartFailures=\(appSnapshot.captureStartFailures)",
            "hidCallbacks=\(appSnapshot.hidCallbacks)",
            "hidNonKeyboardDrops=\(appSnapshot.hidNonKeyboardDrops)",
            "hidKeyUpDrops=\(appSnapshot.hidKeyUpDrops)",
            "hidInvalidKeyDrops=\(appSnapshot.hidInvalidKeyDrops)",
            "hidYieldedEvents=\(appSnapshot.hidYieldedEvents)",
            "appReceivedEvents=\(appSnapshot.appReceivedEvents)",
            "resets=\(appSnapshot.resets)",
            "--- engine ---",
            "engine.isStarted=\(engineDiagnostics.isStarted)",
            "engine.pendingEvents=\(engineDiagnostics.pendingEvents)",
            "engine.pendingWordIncrements=\(engineDiagnostics.pendingWordIncrements)",
            "engine.totalIngestedEvents=\(engineDiagnostics.totalIngestedEvents)",
            "engine.totalFlushes=\(engineDiagnostics.totalFlushes)",
            "engine.totalFlushedEvents=\(engineDiagnostics.totalFlushedEvents)",
            "engine.lastIngestAt=\(String(describing: engineDiagnostics.lastIngestAt))",
            "engine.lastFlushAt=\(String(describing: engineDiagnostics.lastFlushAt))",
            "engine.lastFlushError=\(engineDiagnostics.lastFlushError ?? "none")",
            "--- recent log lines ---"
        ] + Array(appSnapshot.lines.suffix(30))

        return lines.joined(separator: "\n")
    }

    private func shouldRunAutomaticUpdateCheck(now: Date) -> Bool {
        UpdateCheckSchedule.shouldRunAutoCheck(
            enabled: autoCheckUpdates,
            lastCheckedAt: lastUpdateCheckDate,
            now: now,
            intervalHours: autoUpdateCheckIntervalHours
        )
    }

    private func recordUpdateCheckDate(_ date: Date) {
        lastUpdateCheckDate = date
        defaults.set(date, forKey: DefaultsKey.lastUpdateCheckAt)
    }

    private func shouldPromptForUpdate(tag: String) -> Bool {
        let lastPromptedTag = defaults.string(forKey: DefaultsKey.lastPromptedUpdateTag)
        return lastPromptedTag != tag
    }

    private func markPromptedUpdateTag(_ tag: String) {
        defaults.set(tag, forKey: DefaultsKey.lastPromptedUpdateTag)
    }

    private func showUpToDateAlert(current: AppVersion) {
        let alert = NSAlert()
        alert.messageText = "Typist is up to date"
        alert.informativeText = "You are running Typist \(current.description)."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showUpdateAvailableAlert(current: AppVersion, latest: UpdateRelease) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = """
        Typist \(latest.version.description) is available (you have \(current.description)).

        \(Self.releaseNotesSnippet(from: latest.notes))

        If you installed Typist via Homebrew, run:
        brew upgrade --cask typist
        """
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "Not Now")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(latest.htmlURL)
        }
    }

    private func showUpdateErrorAlert(reason: UpdateCheckError) {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = reason.userMessage
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func boolDefault(
        forKey key: String,
        defaults: UserDefaults,
        defaultValue: Bool
    ) -> Bool {
        if let value = defaults.object(forKey: key) as? Bool {
            return value
        }
        return defaultValue
    }

    private static func doubleDefault(
        forKey key: String,
        defaults: UserDefaults,
        defaultValue: Double
    ) -> Double {
        if let value = defaults.object(forKey: key) as? Double {
            return value
        }
        return defaultValue
    }

    private static func shouldDisplayUnsignedInstallNotice(defaults: UserDefaults) -> Bool {
        guard !defaults.bool(forKey: DefaultsKey.didDismissUnsignedInstallNotice) else {
            return false
        }

        return Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    private static func unsignedInstallCommands() -> String {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Typist"
        return "xattr -dr com.apple.quarantine /Applications/\(appName).app"
    }

    private static func releaseNotesSnippet(from notes: String) -> String {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Release notes are available on GitHub."
        }

        let lines = trimmed
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return "Release notes are available on GitHub."
        }

        let snippet = lines.prefix(4).joined(separator: "\n")
        return lines.count > 4 ? "\(snippet)\n…" : snippet
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
