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

    /// Keys that produce text changes (letters, numbers, punctuation, space, enter, backspace/delete).
    /// Excludes modifiers alone, arrows, function keys, escape, caps lock.
    public static func isTextProducingKey(_ keyCode: Int) -> Bool {
        textProducingKeyCodes.contains(keyCode)
    }

    /// Modifier keys (Ctrl, Shift, Alt/Option, Cmd).
    public static func isModifierKey(_ keyCode: Int) -> Bool {
        modifierKeyCodes.contains(keyCode)
    }

    /// Arrow/navigation keys.
    public static func isNavigationKey(_ keyCode: Int) -> Bool {
        navigationKeyCodes.contains(keyCode)
    }

    /// Backspace/Delete key.
    public static func isDeleteKey(_ keyCode: Int) -> Bool {
        deleteKeyCodes.contains(keyCode)
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

    private static let modifierKeyCodes: Set<Int> = [
        224, // Left Ctrl
        225, // Left Shift
        226, // Left Alt
        227, // Left Cmd
        228, // Right Ctrl
        229, // Right Shift
        230, // Right Alt
        231  // Right Cmd
    ]

    private static let navigationKeyCodes: Set<Int> = [
        79, // Right
        80, // Left
        81, // Down
        82  // Up
    ]

    private static let deleteKeyCodes: Set<Int> = [
        42, // Backspace/Delete
        76  // Forward Delete
    ]

    // Letters (4-29), numbers (30-39), punctuation/symbols, space, return, tab, backspace/delete
    private static let textProducingKeyCodes: Set<Int> = {
        var keys = Set<Int>()
        // Letters A-Z
        for k in 4...29 { keys.insert(k) }
        // Numbers 0-9
        for k in 30...39 { keys.insert(k) }
        // Return, Backspace, Tab, Space
        keys.formUnion([40, 42, 43, 44])
        // Punctuation: - = [ ] \ ; ' ` , . /
        keys.formUnion([45, 46, 47, 48, 49, 51, 52, 53, 54, 55, 56])
        // Forward delete
        keys.insert(76)
        return keys
    }()
}
