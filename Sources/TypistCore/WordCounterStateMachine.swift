import Foundation

public struct WordCounterStateMachine: Sendable {
    private(set) var inWord = false

    public init() {}

    public mutating func process(event: KeyEvent) -> Bool {
        if event.isSeparator {
            if inWord {
                inWord = false
                return true
            }
            return false
        }

        inWord = true
        return false
    }

    public mutating func reset() {
        inWord = false
    }
}
