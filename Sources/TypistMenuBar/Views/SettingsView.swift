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
                    Text("• Only key usage counts, timestamps, and device class are persisted.")
                    Text("• A 90-day event ring buffer is retained for aggregation integrity.")
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
                    Picker("Icon style", selection: $appModel.statusIconStyle) {
                        ForEach(StatusIconStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }

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
