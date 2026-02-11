import AppKit
import ApplicationServices
import Foundation

enum PermissionsService {
    static func hasInputMonitoringPermission() -> Bool {
        let granted = CGPreflightListenEventAccess()
        AppDiagnostics.shared.recordPermissionCheck(granted: granted)
        return granted
    }

    @discardableResult
    static func requestInputMonitoringPermission(bringToFront: Bool = true) -> Bool {
        if bringToFront {
            NSApp.activate(ignoringOtherApps: true)
        }
        let granted = CGRequestListenEventAccess()
        AppDiagnostics.shared.recordPermissionRequest(granted: granted)
        return granted
    }

    static func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }
        AppDiagnostics.shared.mark("Opening Input Monitoring settings URL")
        NSWorkspace.shared.open(url)
    }
}
