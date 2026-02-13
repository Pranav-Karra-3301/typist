import AppKit
import SwiftUI
import TypistCore

struct MenuPopoverView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                headerSection

                if appModel.showUnsignedInstallNotice {
                    sectionDivider
                    unsignedInstallNoticeSection
                }

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


                sectionDivider
                metricsSection

                sectionDivider
                footerSection
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .padding(4)
        .frame(width: 344)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            HStack(spacing: 6) {
                Text("Typing speed")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                Text("BETA")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
            }

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
        VStack(alignment: .leading, spacing: 8) {
            Text("Most used keys")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))

            let topFive = Array(appModel.snapshot.topKeys.prefix(5))
                .sorted {
                    if $0.count == $1.count { return $0.keyCode < $1.keyCode }
                    return $0.count < $1.count
                }

            if topFive.isEmpty {
                Text("Start typing to populate key rankings.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
            } else {
                topKeysBarChart(keys: topFive)
            }
        }
    }

    private func topKeysBarChart(keys: [TopKeyStat]) -> some View {
        let maxCount = max(1, keys.map(\.count).max() ?? 1)

        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(keys) { key in
                topKeyBar(key, maxCount: maxCount)
            }
        }
    }

    private func topKeyBar(_ key: TopKeyStat, maxCount: Int) -> some View {
        let maxHeight: CGFloat = 92
        let normalized = CGFloat(Double(key.count) / Double(maxCount))
        let fillHeight = max(4, maxHeight * normalized)

        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.22))
                    .frame(height: fillHeight)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(spacing: 2) {
                Text("\(key.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.22))
                    )
                    .padding(.top, 5)

                Spacer(minLength: 0)

                Text(key.keyName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 5)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: maxHeight)
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

    private var unsignedInstallNoticeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unsigned install notice")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))

            Text("This beta build is unsigned and not notarized. If macOS blocks launch, right-click Typist.app and choose Open.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Copy Fix Command") {
                    appModel.copyUnsignedInstallCommandsToClipboard()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Dismiss") {
                    appModel.dismissUnsignedInstallNotice()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.13))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.orange.opacity(0.32), lineWidth: 0.7)
        )
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

            menuActionButton(title: appModel.isCheckingForUpdates ? "Checking for Updates…" : "Check for Updates…") {
                Task {
                    await appModel.checkForUpdates(userInitiated: true)
                }
            }
            .disabled(appModel.isCheckingForUpdates)

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
