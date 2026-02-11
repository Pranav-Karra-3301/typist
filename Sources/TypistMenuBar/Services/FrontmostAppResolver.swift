import AppKit

struct FrontmostAppInfo {
    let bundleID: String?
    let name: String?
    let processID: pid_t
}

enum FrontmostAppResolver {
    static func current() -> FrontmostAppInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        return FrontmostAppInfo(
            bundleID: app.bundleIdentifier,
            name: app.localizedName,
            processID: app.processIdentifier
        )
    }
}
