import Charts
import SwiftUI
import TypistCore

struct TrendChartView: View {
    let timeframe: Timeframe
    let points: [WPMTrendPoint]
    let granularity: TimeBucketGranularity

    private var rateLabel: String {
        switch granularity {
        case .hour: return "W/hr"
        case .day: return "W/day"
        }
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
            Chart(points) { point in
                AreaMark(
                    x: .value("Time", point.bucketStart),
                    y: .value("Rate", point.rate)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.02)],
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
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4))
            }
            .chartYAxis {
                AxisMarks(position: .trailing)
            }
            .chartXAxisLabel(position: .bottom, alignment: .leading) {}
            .chartYAxisLabel(position: .trailing, alignment: .top) {
                Text(rateLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(height: 88)
        }
    }
}
