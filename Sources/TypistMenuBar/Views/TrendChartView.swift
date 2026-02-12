import Charts
import SwiftUI
import TypistCore

struct TrendChartView: View {
    let timeframe: Timeframe
    let points: [WPMTrendPoint]
    let granularity: TimeBucketGranularity

    private var rateLabel: String {
        switch granularity {
        case .fiveMinutes: return "W/5m"
        case .hour: return "W/hr"
        case .day: return "W/day"
        }
    }

    private var latestRate: Double {
        points.last(where: { $0.rate > 0 })?.rate ?? 0
    }

    var body: some View {
        if points.isEmpty {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
                .frame(height: 88)
                .overlay {
                    Text("No speed data yet")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Spacer()
                    if latestRate > 0 {
                        Text("Now: \(Int(latestRate.rounded()))")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.44))
                    }
                }

                Chart(points) { point in
                    AreaMark(
                        x: .value("Time", point.bucketStart),
                        y: .value("Rate", point.rate)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Time", point.bucketStart),
                        y: .value("Rate", point.rate)
                    )
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }
            .chartLegend(.hidden)
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color.white.opacity(0.03))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisTick()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: TypingSpeedChartView.axisDateFormat(for: timeframe))
                                    .font(.system(size: 9, design: .rounded))
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 88)
            }
        }
    }
}
