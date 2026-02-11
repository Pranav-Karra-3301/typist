import SwiftUI
import TypistCore

private enum KeyCapVisual {
    case text(String)
    case symbol(String)
    case stacked(top: String, bottom: String)
    case symbolWithLabel(symbol: String, label: String)
}

private struct KeyboardKeySpec: Identifiable {
    let id: String
    let keyCode: Int?
    let visual: KeyCapVisual
    let widthUnits: CGFloat
    let isSpacer: Bool
}

private enum KeyboardLayoutANSI {
    static let fullRows: [[KeyboardKeySpec]] = [
        [
            keyText("esc", 41, "esc", width: 1.35),
            keySymbolLabel("f1", 58, symbol: "sun.min.fill", label: "F1"),
            keySymbolLabel("f2", 59, symbol: "sun.max.fill", label: "F2"),
            keySymbolLabel("f3", 60, symbol: "rectangle.3.group", label: "F3"),
            keySymbolLabel("f4", 61, symbol: "magnifyingglass", label: "F4"),
            keySymbolLabel("f5", 62, symbol: "microphone.fill", label: "F5"),
            keySymbolLabel("f6", 63, symbol: "moon.fill", label: "F6"),
            keySymbolLabel("f7", 64, symbol: "backward.fill", label: "F7"),
            keySymbolLabel("f8", 65, symbol: "playpause.fill", label: "F8"),
            keySymbolLabel("f9", 66, symbol: "forward.fill", label: "F9"),
            keySymbolLabel("f10", 67, symbol: "speaker.slash.fill", label: "F10"),
            keySymbolLabel("f11", 68, symbol: "speaker.wave.2.fill", label: "F11"),
            keySymbolLabel("f12", 69, symbol: "speaker.wave.3.fill", label: "F12"),
            keySymbol("power", nil, "power", width: 1.35)
        ],
        [
            keyStacked("grave", 53, top: "~", bottom: "`"),
            keyStacked("1", 30, top: "!", bottom: "1"),
            keyStacked("2", 31, top: "@", bottom: "2"),
            keyStacked("3", 32, top: "#", bottom: "3"),
            keyStacked("4", 33, top: "$", bottom: "4"),
            keyStacked("5", 34, top: "%", bottom: "5"),
            keyStacked("6", 35, top: "^", bottom: "6"),
            keyStacked("7", 36, top: "&", bottom: "7"),
            keyStacked("8", 37, top: "*", bottom: "8"),
            keyStacked("9", 38, top: "(", bottom: "9"),
            keyStacked("0", 39, top: ")", bottom: "0"),
            keyStacked("minus", 45, top: "_", bottom: "-"),
            keyStacked("equal", 46, top: "+", bottom: "="),
            keySymbol("delete", 42, "delete.left", width: 1.95)
        ],
        [
            keySymbol("tab", 43, "arrow.right.to.line", width: 1.55),
            keyText("q", 20, "Q"),
            keyText("w", 26, "W"),
            keyText("e", 8, "E"),
            keyText("r", 21, "R"),
            keyText("t", 23, "T"),
            keyText("y", 28, "Y"),
            keyText("u", 24, "U"),
            keyText("i", 12, "I"),
            keyText("o", 18, "O"),
            keyText("p", 19, "P"),
            keyStacked("leftBracket", 47, top: "{", bottom: "["),
            keyStacked("rightBracket", 48, top: "}", bottom: "]"),
            keyStacked("backslash", 49, top: "|", bottom: "\\", width: 1.35)
        ],
        [
            keyText("caps", 57, "⇪", width: 1.95),
            keyText("a", 4, "A"),
            keyText("s", 22, "S"),
            keyText("d", 7, "D"),
            keyText("f", 9, "F"),
            keyText("g", 10, "G"),
            keyText("h", 11, "H"),
            keyText("j", 13, "J"),
            keyText("k", 14, "K"),
            keyText("l", 15, "L"),
            keyStacked("semicolon", 51, top: ":", bottom: ";"),
            keyStacked("quote", 52, top: "\"", bottom: "'"),
            keyText("return", 40, "↩", width: 2.25)
        ],
        [
            keyText("leftShift", 225, "⇧", width: 2.4),
            keyText("z", 29, "Z"),
            keyText("x", 27, "X"),
            keyText("c", 6, "C"),
            keyText("v", 25, "V"),
            keyText("b", 5, "B"),
            keyText("n", 17, "N"),
            keyText("m", 16, "M"),
            keyStacked("comma", 54, top: "<", bottom: ","),
            keyStacked("period", 55, top: ">", bottom: "."),
            keyStacked("slash", 56, top: "?", bottom: "/"),
            keyText("rightShift", 229, "⇧", width: 2.4)
        ],
        [
            spacer("arrowTopSpacerFn", width: 1.2),
            spacer("arrowTopSpacerCtrl", width: 1.35),
            spacer("arrowTopSpacerOpt", width: 1.35),
            spacer("arrowTopSpacerCmd", width: 1.5),
            spacer("arrowTopSpacerSpace", width: 5.55),
            spacer("arrowTopSpacerCmd2", width: 1.5),
            spacer("arrowTopSpacerOpt2", width: 1.35),
            spacer("arrowTopSpacerLeft", width: 1),
            keySymbol("upArrow", 82, "arrow.up", width: 1),
            spacer("arrowTopSpacerRight", width: 1)
        ],
        [
            keyText("fn", nil, "fn", width: 1.2),
            keyText("leftControl", 224, "⌃", width: 1.35),
            keyText("leftOption", 226, "⌥", width: 1.35),
            keyText("leftCommand", 227, "⌘", width: 1.5),
            keyText("space", 44, "space", width: 5.55),
            keyText("rightCommand", 231, "⌘", width: 1.5),
            keyText("rightOption", 230, "⌥", width: 1.35),
            keySymbol("leftArrow", 80, "arrow.left", width: 1),
            keySymbol("downArrow", 81, "arrow.down", width: 1),
            keySymbol("rightArrow", 79, "arrow.right", width: 1)
        ]
    ]

    static let compactRows: [[KeyboardKeySpec]] = [
        [
            keyText("grave", 53, "~"),
            keyText("1", 30, "1"),
            keyText("2", 31, "2"),
            keyText("3", 32, "3"),
            keyText("4", 33, "4"),
            keyText("5", 34, "5"),
            keyText("6", 35, "6"),
            keyText("7", 36, "7"),
            keyText("8", 37, "8"),
            keyText("9", 38, "9"),
            keyText("0", 39, "0"),
            keyText("minus", 45, "-"),
            keyText("equal", 46, "="),
            keySymbol("delete", 42, "delete.left", width: 1.75)
        ],
        [
            keySymbol("tab", 43, "arrow.right.to.line", width: 1.45),
            keyText("q", 20, "Q"),
            keyText("w", 26, "W"),
            keyText("e", 8, "E"),
            keyText("r", 21, "R"),
            keyText("t", 23, "T"),
            keyText("y", 28, "Y"),
            keyText("u", 24, "U"),
            keyText("i", 12, "I"),
            keyText("o", 18, "O"),
            keyText("p", 19, "P"),
            keyText("leftBracket", 47, "["),
            keyText("rightBracket", 48, "]"),
            keyText("backslash", 49, "\\", width: 1.25)
        ],
        [
            keyText("caps", 57, "⇪", width: 1.75),
            keyText("a", 4, "A"),
            keyText("s", 22, "S"),
            keyText("d", 7, "D"),
            keyText("f", 9, "F"),
            keyText("g", 10, "G"),
            keyText("h", 11, "H"),
            keyText("j", 13, "J"),
            keyText("k", 14, "K"),
            keyText("l", 15, "L"),
            keyText("semicolon", 51, ";"),
            keyText("quote", 52, "'"),
            keyText("return", 40, "↩", width: 2.05)
        ],
        [
            keyText("leftShift", 225, "⇧", width: 2.1),
            keyText("z", 29, "Z"),
            keyText("x", 27, "X"),
            keyText("c", 6, "C"),
            keyText("v", 25, "V"),
            keyText("b", 5, "B"),
            keyText("n", 17, "N"),
            keyText("m", 16, "M"),
            keyText("comma", 54, ","),
            keyText("period", 55, "."),
            keyText("slash", 56, "/"),
            keyText("rightShift", 229, "⇧", width: 2.1)
        ],
        [
            spacer("compactArrowTopCtrl", width: 1.2),
            spacer("compactArrowTopOpt", width: 1.2),
            spacer("compactArrowTopCmd", width: 1.3),
            spacer("compactArrowTopSpace", width: 5.1),
            spacer("compactArrowTopCmd2", width: 1.3),
            spacer("compactArrowTopOpt2", width: 1.2),
            spacer("compactArrowTopLeft", width: 1),
            keySymbol("upArrow", 82, "arrow.up", width: 1),
            spacer("compactArrowTopRight", width: 1)
        ],
        [
            keyText("leftControl", 224, "⌃", width: 1.2),
            keyText("leftOption", 226, "⌥", width: 1.2),
            keyText("leftCommand", 227, "⌘", width: 1.3),
            keyText("space", 44, "space", width: 5.1),
            keyText("rightCommand", 231, "⌘", width: 1.3),
            keyText("rightOption", 230, "⌥", width: 1.2),
            keySymbol("leftArrow", 80, "arrow.left", width: 1),
            keySymbol("downArrow", 81, "arrow.down", width: 1),
            keySymbol("rightArrow", 79, "arrow.right", width: 1)
        ]
    ]

    private static func key(
        _ id: String,
        _ keyCode: Int?,
        _ visual: KeyCapVisual,
        width: CGFloat = 1,
        isSpacer: Bool = false
    ) -> KeyboardKeySpec {
        KeyboardKeySpec(id: id, keyCode: keyCode, visual: visual, widthUnits: width, isSpacer: isSpacer)
    }

    private static func spacer(_ id: String, width: CGFloat) -> KeyboardKeySpec {
        key(id, nil, .text(""), width: width, isSpacer: true)
    }

    private static func keyText(_ id: String, _ keyCode: Int?, _ text: String, width: CGFloat = 1) -> KeyboardKeySpec {
        key(id, keyCode, .text(text), width: width)
    }

    private static func keySymbol(_ id: String, _ keyCode: Int?, _ symbol: String, width: CGFloat = 1) -> KeyboardKeySpec {
        key(id, keyCode, .symbol(symbol), width: width)
    }

    private static func keyStacked(_ id: String, _ keyCode: Int?, top: String, bottom: String, width: CGFloat = 1) -> KeyboardKeySpec {
        key(id, keyCode, .stacked(top: top, bottom: bottom), width: width)
    }

    private static func keySymbolLabel(_ id: String, _ keyCode: Int?, symbol: String, label: String, width: CGFloat = 1) -> KeyboardKeySpec {
        key(id, keyCode, .symbolWithLabel(symbol: symbol, label: label), width: width)
    }
}

struct KeyboardHeatmapView: View {
    let distribution: [TopKeyStat]
    let totalKeystrokes: Int
    @Binding var selectedKeyCode: Int?
    var compact: Bool = false
    var showLegend: Bool = true
    var showSelectedDetails: Bool = true

    private var rows: [[KeyboardKeySpec]] {
        compact ? KeyboardLayoutANSI.compactRows : KeyboardLayoutANSI.fullRows
    }

    private var countByKeyCode: [Int: Int] {
        Dictionary(uniqueKeysWithValues: distribution.map { ($0.keyCode, $0.count) })
    }

    private var maxCount: Int {
        distribution.map(\.count).max() ?? 0
    }

    private var rankByKeyCode: [Int: Int] {
        let ranked = distribution.sorted {
            if $0.count == $1.count { return $0.keyCode < $1.keyCode }
            return $0.count > $1.count
        }

        return Dictionary(uniqueKeysWithValues: ranked.enumerated().map { index, stat in
            (stat.keyCode, index + 1)
        })
    }

    private var keyHeight: CGFloat { compact ? 18 : 34 }
    private var keySpacing: CGFloat { compact ? 3 : 5 }
    private var rowSpacing: CGFloat { compact ? 4 : 7 }
    private var cornerRadius: CGFloat { compact ? 4 : 6 }

    private var minUnitWidth: CGFloat { compact ? 8.5 : 16 }
    private var maxUnitWidth: CGFloat { compact ? 14.5 : 30 }

    private var gridHeight: CGFloat {
        keyHeight * CGFloat(rows.count) + rowSpacing * CGFloat(max(0, rows.count - 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 11) {
            GeometryReader { proxy in
                let unitWidth = resolvedUnitWidth(for: proxy.size.width)
                keyGrid(unitWidth: unitWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: gridHeight)

            if showLegend {
                legend
            }

            if showSelectedDetails {
                selectedKeyDetails
            }
        }
    }

    private func keyGrid(unitWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: keySpacing) {
                    ForEach(row) { key in
                        keyCap(for: key, unitWidth: unitWidth)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyCap(for key: KeyboardKeySpec, unitWidth: CGFloat) -> some View {
        if key.isSpacer {
            Color.clear
                .frame(width: key.widthUnits * unitWidth, height: keyHeight)
        } else {
            let count = key.keyCode.flatMap { countByKeyCode[$0] } ?? 0
            let intensity = key.keyCode.map(heatIntensity(for:)) ?? 0
            let isSelected = key.keyCode != nil && selectedKeyCode == key.keyCode

            Button {
                guard let keyCode = key.keyCode else { return }
                selectedKeyCode = selectedKeyCode == keyCode ? nil : keyCode
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(keyFill(intensity: intensity, isSelected: isSelected))

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            isSelected ? Color.white.opacity(0.65) : Color.white.opacity(0.12),
                            lineWidth: isSelected ? 1.1 : 0.7
                        )

                    VStack(spacing: compact ? 0 : 1) {
                        keyVisualView(key.visual)

                        if !compact && count > 0 {
                            Text(shortCount(count))
                                .font(.system(size: 8, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.58))
                        }
                    }
                    .padding(.horizontal, compact ? 2 : 4)
                }
                .frame(width: key.widthUnits * unitWidth, height: keyHeight)
            }
            .buttonStyle(.plain)
            .help(keyHelpText(for: key, count: count))
        }
    }

    @ViewBuilder
    private func keyVisualView(_ visual: KeyCapVisual) -> some View {
        switch visual {
        case let .text(label):
            Text(label)
                .font(.system(size: compact ? 8 : 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

        case let .symbol(systemName):
            Image(systemName: systemName)
                .font(.system(size: compact ? 8 : 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

        case let .stacked(top, bottom):
            VStack(spacing: compact ? 0 : 1) {
                if !compact {
                    Text(top)
                        .font(.system(size: 7, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Text(bottom)
                    .font(.system(size: compact ? 8 : 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }

        case let .symbolWithLabel(symbol, label):
            VStack(spacing: compact ? 0 : 1) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 8 : 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                if !compact {
                    Text(label)
                        .font(.system(size: 7, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
    }

    private var selectedKeyDetails: some View {
        Group {
            if let selectedKeyCode {
                let count = countByKeyCode[selectedKeyCode, default: 0]
                let rank = rankByKeyCode[selectedKeyCode]
                let share = totalKeystrokes > 0 ? (Double(count) / Double(totalKeystrokes)) : 0

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(KeyboardKeyMapper.displayName(for: selectedKeyCode))
                            .font(.system(size: compact ? 10 : 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.95))

                        Text("\(formatCount(count)) presses • \(percent(share)) share")
                            .font(.system(size: compact ? 9 : 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                    }

                    Spacer()

                    Text(rank.map { "#\($0)" } ?? "N/A")
                        .font(.system(size: compact ? 10 : 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.84))
                }
                .padding(compact ? 7 : 9)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.06))
                )
            } else {
                Text("Click any key to inspect count, share, and rank.")
                    .font(.system(size: compact ? 9 : 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Text("Less")
                .font(.system(size: compact ? 8 : 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))

            LinearGradient(
                colors: [
                    keyFill(intensity: 0, isSelected: false),
                    keyFill(intensity: 0.5, isSelected: false),
                    keyFill(intensity: 1, isSelected: false)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: compact ? 120 : 180, height: 8)
            .clipShape(Capsule())

            Text("More")
                .font(.system(size: compact ? 8 : 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private func resolvedUnitWidth(for availableWidth: CGFloat) -> CGFloat {
        let width = max(availableWidth, 120)
        let candidates = rows.map { row -> CGFloat in
            let units = row.reduce(CGFloat.zero) { $0 + $1.widthUnits }
            let gaps = CGFloat(max(0, row.count - 1)) * keySpacing
            return (width - gaps) / max(units, 0.1)
        }

        let proposed = floor((candidates.min() ?? minUnitWidth) * 100) / 100
        return max(minUnitWidth, min(maxUnitWidth, proposed))
    }

    private func keyHelpText(for key: KeyboardKeySpec, count: Int) -> String {
        guard let keyCode = key.keyCode else {
            return ""
        }
        return "\(KeyboardKeyMapper.displayName(for: keyCode)): \(count) presses"
    }

    private func heatIntensity(for keyCode: Int) -> Double {
        guard maxCount > 0 else { return 0 }
        let count = countByKeyCode[keyCode, default: 0]
        return min(1, Double(count) / Double(maxCount))
    }

    private func keyFill(intensity: Double, isSelected: Bool) -> Color {
        if isSelected {
            return Color.white.opacity(0.26)
        }

        let base = Color.white.opacity(0.055)
        let hot = Color.white.opacity(0.11 + (intensity * 0.24))
        return intensity > 0 ? hot : base
    }

    private func shortCount(_ count: Int) -> String {
        switch count {
        case 10_000...:
            return String(format: "%.1fk", Double(count) / 1000)
        case 1_000...:
            return "\(count / 1000)k"
        default:
            return "\(count)"
        }
    }

    private func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
}
