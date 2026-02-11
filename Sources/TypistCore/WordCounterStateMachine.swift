import Foundation

public struct WordCounterStateMachine: Sendable {
    private(set) var inWord = false
    private(set) var wordHasChars = false

    public init() {}

    /// Process a key event and return true if a word boundary was crossed (word committed).
    public mutating func process(event: KeyEvent) -> Bool {
        if event.isSeparator {
            if inWord && wordHasChars {
                inWord = false
                wordHasChars = false
                return true
            }
            // Repeated separators while not in a word: no word committed
            inWord = false
            return false
        }

        // Non-separator key
        if !KeyboardKeyMapper.isModifierKey(event.keyCode) &&
           !KeyboardKeyMapper.isNavigationKey(event.keyCode) {
            inWord = true
            wordHasChars = true
        }
        return false
    }

    /// Flush the last word at session end.
    /// Returns true if there was an in-progress word that should be counted.
    public mutating func flushLastWord() -> Bool {
        if inWord && wordHasChars {
            inWord = false
            wordHasChars = false
            return true
        }
        return false
    }

    public mutating func reset() {
        inWord = false
        wordHasChars = false
    }
}
