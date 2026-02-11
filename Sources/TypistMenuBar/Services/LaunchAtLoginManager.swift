import Foundation
import Combine
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var lastError: String?

    init() {
        refresh()
    }

    func refresh() {
        if #available(macOS 13.0, *) {
            isEnabled = SMAppService.mainApp.status == .enabled
        } else {
            isEnabled = false
        }
    }

    func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
            refresh()
        }
    }
}
