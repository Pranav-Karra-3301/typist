import Charts
import SwiftUI
import TypistCore

struct TypingSpeedChartView: View {
    let timeframe: Timeframe
    let points: [TypingSpeedTrendPoint]

    private var hasData: Bool {
        points.contains { $0.flowWPM > 0 }
    }

    private var averageFlowWPM: Double {
        let validPoints = points.filter { $0.activeSecondsFlow > 0 }
        guard !validPoints.isEmpty else { return 0 }
        let totalWords = validPoints.reduce(0) { $0 + $1.words }
        let totalSeconds = validPoints.reduce(0.0) { $0 + $1.activeSecondsFlow }
        return totalSeconds > 0 ? Double(totalWords) / (totalSeconds / 60.0) : 0
    }

    var body: some View {
        if !hasData {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
                .frame(height: 88)
                .overlay {
                    Text("Start typing to measure speed")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Avg Flow: \(Int(averageFlowWPM.rounded())) WPM")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }

                Chart(points) { point in
                    AreaMark(
                        x: .value("Time", point.bucketStart),
                        y: .value("Flow WPM", point.flowWPM)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.green.opacity(0.2), Color.green.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Time", point.bucketStart),
                        y: .value("Flow WPM", point.flowWPM)
                    )
                    .foregroundStyle(Color.green.opacity(0.82))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .chartYAxis {
                    AxisMarks(position: .trailing)
                }
                .chartXAxisLabel(position: .bottom, alignment: .leading) {}
                .chartYAxisLabel(position: .trailing, alignment: .top) {
                    Text("WPM")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(height: 76)
            }
        }
    }
}
