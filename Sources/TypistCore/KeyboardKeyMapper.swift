import Foundation

public enum KeyboardKeyMapper {
    public static let validKeyCodeRange: ClosedRange<Int> = 4...231

    private static let names: [Int: String] = [
        4: "A", 5: "B", 6: "C", 7: "D", 8: "E", 9: "F", 10: "G", 11: "H", 12: "I", 13: "J", 14: "K", 15: "L", 16: "M", 17: "N", 18: "O", 19: "P", 20: "Q", 21: "R", 22: "S", 23: "T", 24: "U", 25: "V", 26: "W", 27: "X", 28: "Y", 29: "Z",
        30: "1", 31: "2", 32: "3", 33: "4", 34: "5", 35: "6", 36: "7", 37: "8", 38: "9", 39: "0",
        40: "Return", 41: "Escape", 42: "Delete", 43: "Tab", 44: "Space", 45: "-", 46: "=", 47: "[", 48: "]", 49: "\\", 51: ";", 52: "'", 53: "`", 54: ",", 55: ".", 56: "/",
        57: "Caps Lock",
        79: "Right", 80: "Left", 81: "Down", 82: "Up",
        224: "Left Ctrl", 225: "Left Shift", 226: "Left Alt", 227: "Left Cmd",
        228: "Right Ctrl", 229: "Right Shift", 230: "Right Alt", 231: "Right Cmd"
    ]

    public static func displayName(for keyCode: Int) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }

    public static func isTrackableKeyCode(_ keyCode: Int) -> Bool {
        validKeyCodeRange.contains(keyCode)
    }

    public static func isSeparator(_ keyCode: Int) -> Bool {
        separatorKeyCodes.contains(keyCode)
    }

    private static let separatorKeyCodes: Set<Int> = [
        40, // return
        43, // tab
        44, // space
        45, // -
        46, // =
        47, // [
        48, // ]
        49, // \\
        51, // ;
        52, // '
        53, // `
        54, // ,
        55, // .
        56  // /
    ]
}
