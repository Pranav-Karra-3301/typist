import AppKit
import SwiftUI
import TypistCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appModel: AppModel?
    private var menuBarController: MenuBarController?
    private var settingsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let databaseURL = try Self.databaseURL()
            AppDiagnostics.shared.mark("Using SQLite database at \(databaseURL.path)")
            let store = try SQLiteStore(databaseURL: databaseURL)
            let metricsEngine = MetricsEngine(store: store, queryService: store)
            let captureService = HIDKeyboardCaptureService()
            let launchManager = LaunchAtLoginManager()
            let updateService = UpdateService.makeDefault()

            let model = AppModel(
                metricsEngine: metricsEngine,
                store: store,
                captureService: captureService,
                launchAtLoginManager: launchManager,
                updateService: updateService
            )

            let controller = MenuBarController(appModel: model)

            model.statusItemStateHandler = { [weak controller] state in
                controller?.applyStatusItemState(state)
            }
            model.openSettingsHandler = { [weak self] in
                self?.showSettingsWindow()
            }

            appModel = model
            menuBarController = controller
            scheduleMenuBarRecoveryIfNeeded()

            Task {
                await model.start()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Typist failed to launch"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appModel else {
            return .terminateNow
        }

        Task { @MainActor in
            await appModel.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return false
    }

    private func showSettingsWindow() {
        guard let appModel else { return }

        if let window = settingsWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = SettingsView(appModel: appModel)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = "Typist Settings"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false

        let windowController = NSWindowController(window: window)
        settingsWindowController = windowController
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func scheduleMenuBarRecoveryIfNeeded() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self else { return }
            guard settingsWindowController?.window?.isVisible != true else { return }
            guard menuBarController?.hasStatusItemButton == false else { return }

            AppDiagnostics.shared.mark("Status item unavailable at launch; opening Settings window")
            showSettingsWindow()
        }
    }

    private static func databaseURL() throws -> URL {
        let appSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let typistDirectory = appSupportDirectory.appendingPathComponent("Typist", isDirectory: true)
        try FileManager.default.createDirectory(at: typistDirectory, withIntermediateDirectories: true)

        return typistDirectory.appendingPathComponent("typist.sqlite3", isDirectory: false)
    }
}
