import AppKit
import SwiftUI
import TypistCore

struct MenuPopoverView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                )

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    headerSection
                    sectionDivider
                    timeframeSection
                    sectionDivider
                    typingSpeedSection
                    sectionDivider
                    chartSection
                    sectionDivider
                    topAppsSection

                    if appModel.showHeatmapInPopover {
                        sectionDivider
                        heatmapSection
                    }

                    sectionDivider
                    topKeysSection

                    if appModel.showDiagnosticsInPopover {
                        sectionDivider
                        diagnosticsSection
                    }

                    sectionDivider
                    metricsSection

                    sectionDivider
                    footerSection
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
        }
        .padding(8)
        .frame(width: 344)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                summaryMetric(title: "Keystrokes", value: formatCount(appModel.snapshot.totalKeystrokes))
                summaryMetric(title: "Words", value: formatCount(appModel.snapshot.totalWords))
                summaryMetric(title: "Flow WPM", value: String(format: "%.1f", appModel.snapshot.flowWPM))
            }
        }
    }

    private var timeframeSection: some View {
        Picker("Timeframe", selection: Binding(
            get: { appModel.selectedTimeframe },
            set: { appModel.selectedTimeframe = $0 }
        )) {
            ForEach(Timeframe.allCases, id: \.self) { timeframe in
                Text(timeframe.title).tag(timeframe)
            }
        }
        .pickerStyle(.segmented)
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keyboard mix")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))

            let breakdown = appModel.snapshot.deviceBreakdown
            let total = max(1, breakdown.builtIn + breakdown.external + breakdown.unknown)

            infoRow(label: "Built-in", value: "\(formatCount(breakdown.builtIn)) • \(Int((Double(breakdown.builtIn) / Double(total) * 100).rounded()))%")
            infoRow(label: "External", value: "\(formatCount(breakdown.external)) • \(Int((Double(breakdown.external) / Double(total) * 100).rounded()))%")
            infoRow(label: "Unknown", value: "\(formatCount(breakdown.unknown)) • \(Int((Double(breakdown.unknown) / Double(total) * 100).rounded()))%")

            if appModel.snapshot.pasteEvents > 0 {
                Divider().overlay(Color.white.opacity(0.08))

                Text("Paste activity")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))

                infoRow(label: "Paste events", value: formatCount(appModel.snapshot.pasteEvents))
                infoRow(label: "Pasted words (est.)", value: formatCount(appModel.snapshot.pastedWordsEst))
                infoRow(label: "Assisted WPM", value: String(format: "%.1f", appModel.snapshot.assistedWPM))
            }
        }
    }

    private var typingSpeedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Typing speed")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))

            TypingSpeedChartView(
                timeframe: appModel.snapshot.timeframe,
                points: appModel.snapshot.typingSpeedTrendSeries
            )

            if appModel.snapshot.flowWPM > 0 || appModel.snapshot.skillWPM > 0 {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green.opacity(0.82))
                            .frame(width: 6, height: 6)
                        Text("Flow: \(String(format: "%.1f", appModel.snapshot.flowWPM)) WPM")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.66))
                    }
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.blue.opacity(0.72))
                            .frame(width: 6, height: 6)
                        Text("Skill: \(String(format: "%.1f", appModel.snapshot.skillWPM)) WPM")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.66))
                    }
                }
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Word output")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))

            TrendChartView(
                timeframe: appModel.snapshot.timeframe,
                points: appModel.snapshot.wpmTrendSeries,
                granularity: appModel.snapshot.timeframe.trendGranularity
            )
        }
    }

    private var topAppsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Top apps by words")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))

                Spacer()

                Button("View all") {
                    appModel.openSettings(tab: .analytics)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
            }

            AppWordListView(
                apps: appModel.snapshot.topAppsByWords,
                maxItems: 5,
                emptyMessage: "Start typing across apps to build distribution.",
                style: .popover
            )
        }
    }

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Keyboard Heatmap")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))

                Spacer()

                Button("Open full view") {
                    appModel.openSettings(tab: .keyboard)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
            }

            KeyboardHeatmapView(
                distribution: appModel.snapshot.keyDistribution,
                totalKeystrokes: appModel.snapshot.totalKeystrokes,
                selectedKeyCode: $appModel.selectedHeatmapKeyCode,
                compact: true,
                showLegend: false,
                showSelectedDetails: true
            )
        }
    }

    private var topKeysSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Most used keys")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))

            if appModel.snapshot.topKeys.isEmpty {
                Text("Start typing to populate key rankings.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
            } else {
                ForEach(Array(appModel.snapshot.topKeys.prefix(5).enumerated()), id: \.element.id) { index, key in
                    infoRow(label: "\(index + 1). \(key.keyName)", value: formatCount(key.count))
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Diagnostics")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))

                Spacer()

                Button("Copy") {
                    appModel.copyDiagnosticsToClipboard()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
            }

            Text(appModel.debugSummary)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.68))
                .textSelection(.enabled)
        }
    }

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !appModel.permissionGranted {
                HStack(spacing: 8) {
                    Button("Enable Input Monitoring") {
                        Task {
                            await appModel.requestPermission()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Open System Settings") {
                        appModel.openInputMonitoringSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { appModel.launchAtLoginEnabled },
                    set: { appModel.setLaunchAtLogin($0) }
                )
            )
            .toggleStyle(.checkbox)
            .font(.system(size: 11, weight: .medium, design: .rounded))

            menuActionRows
        }
    }

    private var menuActionRows: some View {
        VStack(spacing: 0) {
            menuActionButton(title: "More") {
                appModel.openSettings(tab: .statusIcon)
            }

            Divider().overlay(Color.white.opacity(0.08))

            menuActionButton(title: "Settings…") {
                appModel.openSettings()
            }

            Divider().overlay(Color.white.opacity(0.08))

            menuActionButton(title: "Reset Stats") {
                Task {
                    await appModel.resetStats()
                }
            }

            Divider().overlay(Color.white.opacity(0.08))

            menuActionButton(title: "Quit Typist") {
                NSApp.terminate(nil)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
        )
    }

    private func menuActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))
        }
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))

            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sectionDivider: some View {
        Divider().overlay(Color.white.opacity(0.1))
    }

    private func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
