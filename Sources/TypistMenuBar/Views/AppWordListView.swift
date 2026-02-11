import AppKit
import SwiftUI
import TypistCore

struct AppWordListView: View {
    enum Style {
        case popover
        case settings

        var emptyColor: Color {
            switch self {
            case .popover: return .white.opacity(0.56)
            case .settings: return .secondary
            }
        }

        var labelColor: Color {
            switch self {
            case .popover: return .white.opacity(0.72)
            case .settings: return .primary
            }
        }

        var valueColor: Color {
            switch self {
            case .popover: return .white.opacity(0.84)
            case .settings: return .primary
            }
        }

        var fallbackIconColor: Color {
            switch self {
            case .popover: return .white.opacity(0.56)
            case .settings: return .secondary
            }
        }
    }

    let apps: [AppWordStat]
    let maxItems: Int
    let emptyMessage: String
    let style: Style

    var body: some View {
        if apps.isEmpty {
            Text(emptyMessage)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(style.emptyColor)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(apps.prefix(maxItems))) { app in
                    HStack(spacing: 8) {
                        AppIconView(bundleID: app.bundleID, style: style)
                        Text(app.appName)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(style.labelColor)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 8)

                        Text(formattedCount(app.wordCount))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(style.valueColor)
                    }
                }
            }
        }
    }

    private func formattedCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private struct AppIconView: View {
    let bundleID: String
    let style: AppWordListView.Style

    var body: some View {
        if let icon = AppIconProvider.icon(for: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(style.fallbackIconColor)
                .frame(width: 14, height: 14)
        }
    }
}

private enum AppIconProvider {
    static let cache = NSCache<NSString, NSImage>()

    static func icon(for bundleID: String) -> NSImage? {
        guard bundleID != AppIdentity.unknownBundleID else {
            return nil
        }

        let cacheKey = bundleID as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 14, height: 14)
        cache.setObject(icon, forKey: cacheKey)
        return icon
    }
}
