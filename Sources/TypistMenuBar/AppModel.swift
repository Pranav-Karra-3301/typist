import AppKit
import Foundation
import Combine
import TypistCore

@MainActor
final class AppModel: ObservableObject {
    private enum DefaultsKey {
        static let didAttemptPermissionPrompt = "typist.didAttemptPermissionPrompt"
    }

    @Published var selectedTimeframe: Timeframe = .h12 {
        didSet {
            Task { await refreshSelectedTimeframe() }
        }
    }

    @Published private(set) var snapshot: StatsSnapshot
    @Published private(set) var permissionGranted = false
    @Published private(set) var captureRunning = false
    @Published private(set) var statusMessage = "Checking permissions…"
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchErrorMessage: String?
    @Published private(set) var debugSummary = "Diagnostics loading…"
    @Published private(set) var debugLines: [String] = []

    var statusTitleHandler: ((String) -> Void)?
    var openSettingsHandler: (() -> Void)?

    private let metricsEngine: MetricsEngine
    private let store: StatsResetting
    private let queryService: StatsQuerying
    private let captureService: KeyboardCaptureProviding
    private let launchAtLoginManager: LaunchAtLoginManager
    private let diagnostics = AppDiagnostics.shared

    private var captureTask: Task<Void, Never>?
    private var popoverRefreshTask: Task<Void, Never>?
    private var statusRefreshTask: Task<Void, Never>?
    private var snapshotRefreshCount = 0

    init(
        metricsEngine: MetricsEngine,
        store: StatsResetting,
        queryService: StatsQuerying,
        captureService: KeyboardCaptureProviding,
        launchAtLoginManager: LaunchAtLoginManager
    ) {
        self.metricsEngine = metricsEngine
        self.store = store
        self.queryService = queryService
        self.captureService = captureService
        self.launchAtLoginManager = launchAtLoginManager
        self.snapshot = .empty(timeframe: .h12)
        self.launchAtLoginEnabled = launchAtLoginManager.isEnabled
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
                await refreshDiagnostics()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    await refreshPermissionAndCaptureState()
                    await refreshSelectedTimeframe()
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
            await refreshDiagnostics()
        } catch {
            statusMessage = "Failed to reset stats: \(error.localizedDescription)"
            diagnostics.mark("Reset stats failed: \(error.localizedDescription)")
        }
    }

    func openSettings() {
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
            statusTitleHandler?("\(latest.totalKeystrokes)")
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
                await refreshStatusTitle()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func refreshStatusTitle() async {
        do {
            let statusSnapshot = try await queryService.snapshot(for: .h24, now: Date())
            statusTitleHandler?("\(statusSnapshot.totalKeystrokes)")
            await refreshDiagnostics()
        } catch {
            statusTitleHandler?("--")
            diagnostics.mark("Status title refresh failed")
        }
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
}
