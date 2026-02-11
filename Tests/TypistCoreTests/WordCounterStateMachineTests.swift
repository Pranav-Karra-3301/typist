import XCTest
@testable import TypistCore

final class WordCounterStateMachineTests: XCTestCase {
    func testCountsWordOnSeparatorBoundary() {
        var machine = WordCounterStateMachine()

        let a = KeyEvent(timestamp: Date(), keyCode: 4, isSeparator: false, deviceClass: .builtIn)
        let space = KeyEvent(timestamp: Date(), keyCode: 44, isSeparator: true, deviceClass: .builtIn)

        XCTAssertFalse(machine.process(event: a))
        XCTAssertTrue(machine.process(event: space))
    }

    func testRepeatedSeparatorsDoNotDoubleCount() {
        var machine = WordCounterStateMachine()
        let separator = KeyEvent(timestamp: Date(), keyCode: 44, isSeparator: true, deviceClass: .external)

        XCTAssertFalse(machine.process(event: separator))
        XCTAssertFalse(machine.process(event: separator))
    }

    func testBackspaceLikeNonSeparatorDoesNotIncrementUntilSeparator() {
        var machine = WordCounterStateMachine()

        let letter = KeyEvent(timestamp: Date(), keyCode: 4, isSeparator: false, deviceClass: .unknown)
        let delete = KeyEvent(timestamp: Date(), keyCode: 42, isSeparator: false, deviceClass: .unknown)
        let returnKey = KeyEvent(timestamp: Date(), keyCode: 40, isSeparator: true, deviceClass: .unknown)

        XCTAssertFalse(machine.process(event: letter))
        XCTAssertFalse(machine.process(event: delete))
        XCTAssertTrue(machine.process(event: returnKey))
    }

    func testPunctuationSeparatorCountsWordBoundary() {
        var machine = WordCounterStateMachine()

        let letter = KeyEvent(timestamp: Date(), keyCode: 4, isSeparator: false, deviceClass: .builtIn)
        let period = KeyEvent(timestamp: Date(), keyCode: 55, isSeparator: true, deviceClass: .builtIn)

        XCTAssertFalse(machine.process(event: letter))
        XCTAssertTrue(machine.process(event: period))
    }

    func testModifierKeysDoNotEndWord() {
        var machine = WordCounterStateMachine()

        let letter = KeyEvent(timestamp: Date(), keyCode: 4, isSeparator: false, deviceClass: .unknown)
        let shift = KeyEvent(timestamp: Date(), keyCode: 225, isSeparator: false, deviceClass: .unknown)
        let space = KeyEvent(timestamp: Date(), keyCode: 44, isSeparator: true, deviceClass: .unknown)

        XCTAssertFalse(machine.process(event: letter))
        XCTAssertFalse(machine.process(event: shift))
        XCTAssertTrue(machine.process(event: space))
    }

    func testFlushLastWordCountsIncompleteWord() {
        var machine = WordCounterStateMachine()

        let letter = KeyEvent(timestamp: Date(), keyCode: 4, isSeparator: false, deviceClass: .builtIn)
        XCTAssertFalse(machine.process(event: letter))

        // No space pressed — flush should count the incomplete word
        XCTAssertTrue(machine.flushLastWord())
    }

    func testFlushLastWordReturnsFalseWhenEmpty() {
        var machine = WordCounterStateMachine()

        // No typing at all — nothing to flush
        XCTAssertFalse(machine.flushLastWord())
    }

    func testModifierKeysDoNotSetWordHasChars() {
        var machine = WordCounterStateMachine()

        // Press only modifier keys (224-231)
        let leftCtrl = KeyEvent(timestamp: Date(), keyCode: 224, isSeparator: false, deviceClass: .builtIn)
        let leftShift = KeyEvent(timestamp: Date(), keyCode: 225, isSeparator: false, deviceClass: .builtIn)
        let leftAlt = KeyEvent(timestamp: Date(), keyCode: 226, isSeparator: false, deviceClass: .builtIn)
        let leftCmd = KeyEvent(timestamp: Date(), keyCode: 227, isSeparator: false, deviceClass: .builtIn)

        XCTAssertFalse(machine.process(event: leftCtrl))
        XCTAssertFalse(machine.process(event: leftShift))
        XCTAssertFalse(machine.process(event: leftAlt))
        XCTAssertFalse(machine.process(event: leftCmd))

        // wordHasChars should still be false; flush returns false
        XCTAssertFalse(machine.flushLastWord())
    }

    func testNavigationKeysDoNotCommitWords() {
        var machine = WordCounterStateMachine()

        // Type a letter
        let letter = KeyEvent(timestamp: Date(), keyCode: 4, isSeparator: false, deviceClass: .builtIn)
        XCTAssertFalse(machine.process(event: letter))

        // Press arrow key (navigation, keyCode 79 = Right)
        let arrow = KeyEvent(timestamp: Date(), keyCode: 79, isSeparator: false, deviceClass: .builtIn)
        XCTAssertFalse(machine.process(event: arrow))

        // Press space — word should be committed because letter set wordHasChars
        let space = KeyEvent(timestamp: Date(), keyCode: 44, isSeparator: true, deviceClass: .builtIn)
        XCTAssertTrue(machine.process(event: space))
    }

    func testRepeatedSpacesDoNotCreatePhantomWords() {
        var machine = WordCounterStateMachine()

        // Type "hello"
        for keyCode in [11, 8, 15, 15, 18] { // H, E, L, L, O
            XCTAssertFalse(machine.process(event: KeyEvent(timestamp: Date(), keyCode: keyCode, isSeparator: false, deviceClass: .builtIn)))
        }

        // First space commits the word
        let space = KeyEvent(timestamp: Date(), keyCode: 44, isSeparator: true, deviceClass: .builtIn)
        XCTAssertTrue(machine.process(event: space))

        // Additional spaces should NOT create phantom words
        XCTAssertFalse(machine.process(event: space))
        XCTAssertFalse(machine.process(event: space))
    }
}
