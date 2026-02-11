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
}
