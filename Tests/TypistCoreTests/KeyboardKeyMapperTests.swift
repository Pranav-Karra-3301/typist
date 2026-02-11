import XCTest
@testable import TypistCore

final class KeyboardKeyMapperTests: XCTestCase {
    func testValidKeyCodeRange() {
        XCTAssertTrue(KeyboardKeyMapper.isTrackableKeyCode(4))
        XCTAssertTrue(KeyboardKeyMapper.isTrackableKeyCode(44))
        XCTAssertTrue(KeyboardKeyMapper.isTrackableKeyCode(231))

        XCTAssertFalse(KeyboardKeyMapper.isTrackableKeyCode(0))
        XCTAssertFalse(KeyboardKeyMapper.isTrackableKeyCode(3))
        XCTAssertFalse(KeyboardKeyMapper.isTrackableKeyCode(232))
        XCTAssertFalse(KeyboardKeyMapper.isTrackableKeyCode(Int(UInt32.max)))
    }

    func testModifierDisplayNames() {
        XCTAssertEqual(KeyboardKeyMapper.displayName(for: 224), "Left Ctrl")
        XCTAssertEqual(KeyboardKeyMapper.displayName(for: 227), "Left Cmd")
        XCTAssertEqual(KeyboardKeyMapper.displayName(for: 231), "Right Cmd")
    }

    func testSpaceIsSeparatorKey() {
        XCTAssertTrue(KeyboardKeyMapper.isSeparator(44))
    }
}
