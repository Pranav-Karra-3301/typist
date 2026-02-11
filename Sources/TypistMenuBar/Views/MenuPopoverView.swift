import AppKit
import SwiftUI
import TypistCore

struct MenuPopoverView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.09, blue: 0.11),
                    Color(red: 0.12, green: 0.13, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    headerSection
                    timeframeSection
                    metricsSection
                    chartSection
                    topKeysSection
                    diagnosticsSection
                    footerSection
                }
                .padding(14)
            }
        }
        .frame(width: 340)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Keyboard")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Text(appModel.captureRunning ? "Live" : "Paused")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(appModel.captureRunning ? Color.cyan : Color.orange)
            }

            Text(appModel.statusMessage)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statCard(title: "Keystrokes", value: formatCount(appModel.snapshot.totalKeystrokes))
                statCard(title: "Words", value: formatCount(appModel.snapshot.totalWords))
            }

            let breakdown = appModel.snapshot.deviceBreakdown
            let total = max(1, breakdown.builtIn + breakdown.external + breakdown.unknown)

            HStack(spacing: 12) {
                deviceTag(label: "Built-in", count: breakdown.builtIn, share: Double(breakdown.builtIn) / Double(total))
                deviceTag(label: "External", count: breakdown.external, share: Double(breakdown.external) / Double(total))
                deviceTag(label: "Unknown", count: breakdown.unknown, share: Double(breakdown.unknown) / Double(total))
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trend")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            TrendChartView(timeframe: appModel.snapshot.timeframe, points: appModel.snapshot.trendSeries)
        }
    }

    private var topKeysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Keys")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            if appModel.snapshot.topKeys.isEmpty {
                Text("Start typing to see key distribution")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(appModel.snapshot.topKeys.prefix(5).enumerated()), id: \.element.id) { index, key in
                    HStack {
                        Text("\(index + 1). \(key.keyName)")
                            .foregroundStyle(.white.opacity(0.9))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                        Spacer()
                        Text(formatCount(key.count))
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                }
            }
        }
    }

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Color.white.opacity(0.12))

            if !appModel.permissionGranted {
                HStack(spacing: 8) {
                    Button("Enable Input Monitoring") {
                        Task {
                            await appModel.requestPermission()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Open Settings") {
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

            if let launchError = appModel.launchErrorMessage {
                Text("Launch setting error: \(launchError)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.orange)
            }

            HStack {
                Button("Reset Stats") {
                    Task {
                        await appModel.resetStats()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Settings…") {
                    appModel.openSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Diagnostics")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()

                Button("Copy Debug") {
                    appModel.copyDiagnosticsToClipboard()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.cyan)
            }

            Text(appModel.debugSummary)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.85))
                .textSelection(.enabled)

            if appModel.debugLines.isEmpty {
                Text("No diagnostic logs yet")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(appModel.debugLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func deviceTag(label: String, count: Int, share: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text("\(formatCount(count))  ·  \(Int((share * 100).rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
