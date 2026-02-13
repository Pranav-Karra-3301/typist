import AppKit
import SwiftUI
import TypistCore

struct SettingsView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        TabView(selection: $appModel.selectedSettingsTab) {
            generalTab
                .tag(SettingsTab.general)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            statusIconTab
                .tag(SettingsTab.statusIcon)
                .tabItem {
                    Label("Status Icon", systemImage: "menubar.rectangle")
                }

            keyboardTab
                .tag(SettingsTab.keyboard)
                .tabItem {
                    Label("Keyboard", systemImage: "square.grid.3x2")
                }

            analyticsTab
                .tag(SettingsTab.analytics)
                .tabItem {
                    Label("Analytics", systemImage: "chart.xyaxis.line")
                }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 560)
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsGroup(
                    title: "General",
                    subtitle: "Startup and menu behavior"
                ) {
                    Toggle(
                        "Open at login",
                        isOn: Binding(
                            get: { appModel.launchAtLoginEnabled },
                            set: { appModel.setLaunchAtLogin($0) }
                        )
                    )

                    Toggle("Show keyboard heatmap in menu popover", isOn: $appModel.showHeatmapInPopover)
                    Toggle("Show diagnostics in menu popover", isOn: $appModel.showDiagnosticsInPopover)

                    if let launchError = appModel.launchErrorMessage {
                        Text("Launch setting error: \(launchError)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                }

                settingsGroup(
                    title: "Privacy",
                    subtitle: "What Typist stores locally"
                ) {
                    Text("• Typed text is never stored.")
                    Text("• Only key usage counts, timestamps, app identity, and device class are persisted.")
                    Text("• A 90-day event ring buffer is retained for aggregation integrity.")
                }

                settingsGroup(
                    title: "Install & Security (Unsigned Build)",
                    subtitle: "How to open Typist if Gatekeeper blocks launch"
                ) {
                    Text("• Homebrew and direct DMG install the same app bundle.")
                    Text("• Homebrew cannot add Apple notarization or trust.")
                    Text("• If blocked, right-click Typist.app and choose Open.")
                    Text("• Terminal fallback:")
                    Text("xattr -dr com.apple.quarantine /Applications/Typist.app")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    HStack(spacing: 10) {
                        Button("Copy Fix Command") {
                            appModel.copyUnsignedInstallCommandsToClipboard()
                        }
                        .buttonStyle(.bordered)

                        if appModel.showUnsignedInstallNotice {
                            Button("Dismiss Startup Reminder") {
                                appModel.dismissUnsignedInstallNotice()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                settingsGroup(
                    title: "Updates",
                    subtitle: "Automatic checks for new beta releases"
                ) {
                    Toggle(
                        "Automatically check for updates",
                        isOn: Binding(
                            get: { appModel.autoCheckUpdates },
                            set: { appModel.autoCheckUpdates = $0 }
                        )
                    )

                    HStack(spacing: 10) {
                        Button(appModel.isCheckingForUpdates ? "Checking…" : "Check for Updates…") {
                            Task {
                                await appModel.checkForUpdates(userInitiated: true)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(appModel.isCheckingForUpdates)

                        if appModel.latestVersionLabel != nil {
                            Button("Open Latest Release") {
                                appModel.openLatestReleasePage()
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()
                    }

                    Text(appModel.updateStatusText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsGroup(
                    title: "Actions",
                    subtitle: "Maintenance and permissions"
                ) {
                    HStack(spacing: 10) {
                        Button("Open Input Monitoring Settings") {
                            appModel.openInputMonitoringSettings()
                        }
                        .buttonStyle(.bordered)

                        Button("Reset All Stats") {
                            Task {
                                await appModel.resetStats()
                            }
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button("Close") {
                            NSApp.keyWindow?.close()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var statusIconTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsGroup(
                    title: "Status Icon",
                    subtitle: "Choose what appears in the menu bar"
                ) {
                    statusIconGrid

                    Toggle("Show monochrome icon", isOn: $appModel.statusIconMonochrome)
                    Toggle("Show text count", isOn: $appModel.showStatusTextCount)

                    Picker("Text metric", selection: $appModel.statusTextMetric) {
                        ForEach(StatusTextMetric.allCases) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    .disabled(!appModel.showStatusTextCount)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var statusIconGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Icon style")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))

            LazyVGrid(columns: statusIconGridColumns, alignment: .leading, spacing: 10) {
                ForEach(StatusIconStyle.allCases) { style in
                    statusIconGridCell(for: style)
                }
            }
        }
    }

    private let statusIconGridColumns = [
        GridItem(.adaptive(minimum: 116), spacing: 10)
    ]

    @ViewBuilder
    private func statusIconGridCell(for style: StatusIconStyle) -> some View {
        let isSelected = style == appModel.statusIconStyle

        Button {
            appModel.statusIconStyle = style
        } label: {
            statusIconGridCellLabel(for: style, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .offset(x: 5, y: -5)
            }
        }
    }

    private func statusIconGridCellLabel(for style: StatusIconStyle, isSelected: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.18), lineWidth: isSelected ? 2 : 1)
                    )

                statusIconPreview(for: style)
            }
            .frame(width: 72, height: 72)

            Text(style.title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.76))
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    private func statusIconPreview(for style: StatusIconStyle) -> some View {
        let previewImage = StatusIconRenderer.monochromeIcon(for: style, size: 28, isTemplate: true)
        return Group {
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(appModel.statusIconMonochrome ? .white : Color.accentColor)
                    .scaleEffect(1.05)
            } else {
                Text("?")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var keyboardTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsGroup(
                    title: "Keyboard Heatmap",
                    subtitle: "Mac ANSI layout • click any key to inspect usage"
                ) {
                    Picker("Timeframe", selection: $appModel.selectedTimeframe) {
                        ForEach(Timeframe.allCases, id: \.self) { timeframe in
                            Text(timeframe.title).tag(timeframe)
                        }
                    }
                    .pickerStyle(.segmented)

                    if appModel.snapshot.totalKeystrokes == 0 {
                        Text("Start typing to build your keyboard heatmap.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        KeyboardHeatmapView(
                            distribution: appModel.snapshot.keyDistribution,
                            totalKeystrokes: appModel.snapshot.totalKeystrokes,
                            selectedKeyCode: $appModel.selectedHeatmapKeyCode,
                            compact: false,
                            showLegend: true,
                            showSelectedDetails: true
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var analyticsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsGroup(
                    title: "Typing Speed",
                    subtitle: "Actual words per minute based on active typing time"
                ) {
                    Picker("Timeframe", selection: $appModel.selectedTimeframe) {
                        ForEach(Timeframe.allCases, id: \.self) { timeframe in
                            Text(timeframe.title).tag(timeframe)
                        }
                    }
                    .pickerStyle(.segmented)

                    TypingSpeedChartView(
                        timeframe: appModel.snapshot.timeframe,
                        points: appModel.snapshot.typingSpeedTrendSeries
                    )
                }

                settingsGroup(
                    title: "Word Output",
                    subtitle: "Words typed per time bucket"
                ) {
                    TrendChartView(
                        timeframe: appModel.snapshot.timeframe,
                        points: appModel.snapshot.wpmTrendSeries,
                        granularity: appModel.snapshot.timeframe.trendGranularity
                    )
                }

                settingsGroup(
                    title: "Words by App",
                    subtitle: "Attributed at word boundary (space/return/punctuation)"
                ) {
                    AppWordListView(
                        apps: appModel.snapshot.topAppsByWords,
                        maxItems: 20,
                        emptyMessage: "Start typing in different apps to populate this list.",
                        style: .settings
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func settingsGroup<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            content()
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.thinMaterial)
        )
    }
}
