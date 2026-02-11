import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private unowned let appModel: AppModel
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    init(appModel: AppModel) {
        self.appModel = appModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()
        configureStatusItem()
        configurePopover()
    }

    func updateStatusTitle(_ title: String) {
        guard let button = statusItem.button else { return }
        if button.image != nil {
            button.title = " \(title)"
        } else {
            button.title = "❀ \(title)"
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
            appModel.setPopoverVisible(false)
            stopDismissMonitoring()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            appModel.setPopoverVisible(true)
            startDismissMonitoring()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        appModel.setPopoverVisible(false)
        stopDismissMonitoring()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = makeStatusIcon()
        button.imagePosition = .imageLeading
        button.title = button.image == nil ? "❀ --" : " --"
        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 340, height: 520)
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MenuPopoverView(appModel: appModel))
    }

    private func startDismissMonitoring() {
        if globalClickMonitor == nil {
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.dismissPopoverIfNeeded()
                }
            }
        }

        if localClickMonitor == nil {
            localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self else { return event }
                guard self.popover.isShown else { return event }

                let popoverWindow = self.popover.contentViewController?.view.window
                let statusWindow = self.statusItem.button?.window
                if event.window === popoverWindow || event.window === statusWindow {
                    return event
                }

                self.dismissPopoverIfNeeded()
                return event
            }
        }
    }

    private func stopDismissMonitoring() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }

        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    private func dismissPopoverIfNeeded() {
        guard popover.isShown else { return }
        popover.performClose(nil)
        appModel.setPopoverVisible(false)
        stopDismissMonitoring()
    }

    private func makeStatusIcon() -> NSImage? {
        let symbolCandidates = ["flower", "camera.macro", "leaf"]
        for symbolName in symbolCandidates {
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Typist") {
                image.isTemplate = true
                return image
            }
        }
        return nil
    }
}
