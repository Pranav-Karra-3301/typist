import AppKit
import Combine
import Foundation
import TypistCore

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case statusIcon
    case keyboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .statusIcon: return "Status Icon"
        case .keyboard: return "Keyboard"
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
        static let statusIconStyle = "typist.statusIconStyle"
        static let showStatusTextCount = "typist.showStatusTextCount"
        static let statusTextMetric = "typist.statusTextMetric"
        static let statusIconMonochrome = "typist.statusIconMonochrome"
        static let showHeatmapInPopover = "typist.showHeatmapInPopover"
        static let showDiagnosticsInPopover = "typist.showDiagnosticsInPopover"
    }

    @Published var selectedTimeframe: Timeframe = .h12 {
        didSet {
            Task { await refreshSelectedTimeframe() }
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

    @Published var statusIconStyle: StatusIconStyle {
        didSet {
            UserDefaults.standard.set(statusIconStyle.rawValue, forKey: DefaultsKey.statusIconStyle)
            publishStatusItemState()
        }
    }

    @Published var showStatusTextCount: Bool {
        didSet {
            UserDefaults.standard.set(showStatusTextCount, forKey: DefaultsKey.showStatusTextCount)
            publishStatusItemState()
        }
    }

    @Published var statusTextMetric: StatusTextMetric {
        didSet {
            UserDefaults.standard.set(statusTextMetric.rawValue, forKey: DefaultsKey.statusTextMetric)
            publishStatusItemState()
        }
    }

    @Published var statusIconMonochrome: Bool {
        didSet {
            UserDefaults.standard.set(statusIconMonochrome, forKey: DefaultsKey.statusIconMonochrome)
            publishStatusItemState()
        }
    }

    @Published var showHeatmapInPopover: Bool {
        didSet {
            UserDefaults.standard.set(showHeatmapInPopover, forKey: DefaultsKey.showHeatmapInPopover)
        }
    }

    @Published var showDiagnosticsInPopover: Bool {
        didSet {
            UserDefaults.standard.set(showDiagnosticsInPopover, forKey: DefaultsKey.showDiagnosticsInPopover)
        }
    }

    var statusItemStateHandler: ((StatusItemState) -> Void)?
    var openSettingsHandler: (() -> Void)?

    private let metricsEngine: MetricsEngine
    private let store: StatsResetting
    private let captureService: KeyboardCaptureProviding
    private let launchAtLoginManager: LaunchAtLoginManager
    private let diagnostics = AppDiagnostics.shared

    private var captureTask: Task<Void, Never>?
    private var popoverRefreshTask: Task<Void, Never>?
    private var statusRefreshTask: Task<Void, Never>?
    private var snapshotRefreshCount = 0
    private var latestStatusKeystrokes = 0
    private var latestStatusWords = 0

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    init(
        metricsEngine: MetricsEngine,
        store: StatsResetting,
        captureService: KeyboardCaptureProviding,
        launchAtLoginManager: LaunchAtLoginManager
    ) {
        let defaults = UserDefaults.standard

        self.metricsEngine = metricsEngine
        self.store = store
        self.captureService = captureService
        self.launchAtLoginManager = launchAtLoginManager
        self.snapshot = .empty(timeframe: .h12)
        self.launchAtLoginEnabled = launchAtLoginManager.isEnabled

        self.statusIconStyle = StatusIconStyle(rawValue: defaults.string(forKey: DefaultsKey.statusIconStyle) ?? "") ?? .dynamic
        self.showStatusTextCount = Self.boolDefault(forKey: DefaultsKey.showStatusTextCount, defaultValue: true)
        self.statusTextMetric = StatusTextMetric(rawValue: defaults.string(forKey: DefaultsKey.statusTextMetric) ?? "") ?? .keystrokes
        self.statusIconMonochrome = Self.boolDefault(forKey: DefaultsKey.statusIconMonochrome, defaultValue: true)
        self.showHeatmapInPopover = Self.boolDefault(forKey: DefaultsKey.showHeatmapInPopover, defaultValue: true)
        self.showDiagnosticsInPopover = Self.boolDefault(forKey: DefaultsKey.showDiagnosticsInPopover, defaultValue: true)
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
        do {
            let latest = try await metricsEngine.snapshot(for: selectedTimeframe, now: Date())
            snapshot = latest
            snapshotRefreshCount += 1
            if snapshotRefreshCount <= 3 || snapshotRefreshCount % 20 == 0 {
                diagnostics.mark("Snapshot refresh: timeframe=\(selectedTimeframe.rawValue) keys=\(latest.totalKeystrokes) words=\(latest.totalWords)")
            }
        } catch {
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
        guard !UserDefaults.standard.bool(forKey: DefaultsKey.didAttemptPermissionPrompt) else { return }
        UserDefaults.standard.set(true, forKey: DefaultsKey.didAttemptPermissionPrompt)

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

    private static func boolDefault(forKey key: String, defaultValue: Bool) -> Bool {
        if let value = UserDefaults.standard.object(forKey: key) as? Bool {
            return value
        }
        return defaultValue
    }
}
