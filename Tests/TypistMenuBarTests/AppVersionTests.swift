import XCTest
@testable import TypistMenuBar

final class AppVersionTests: XCTestCase {
    func testParsesBetaVersionWithTagPrefix() {
        let parsed = AppVersion.parse("v0.1.0-beta.10")

        XCTAssertEqual(parsed?.major, 0)
        XCTAssertEqual(parsed?.minor, 1)
        XCTAssertEqual(parsed?.patch, 0)
        XCTAssertEqual(parsed?.prerelease?.label, "beta")
        XCTAssertEqual(parsed?.prerelease?.number, 10)
    }

    func testStableVersionIsGreaterThanPrerelease() {
        let stable = AppVersion.parse("0.1.0")
        let beta = AppVersion.parse("0.1.0-beta.99")

        XCTAssertNotNil(stable)
        XCTAssertNotNil(beta)
        XCTAssertTrue(stable! > beta!)
    }

    func testHigherBetaNumberWins() {
        let beta9 = AppVersion.parse("0.1.0-beta.9")
        let beta10 = AppVersion.parse("0.1.0-beta.10")

        XCTAssertNotNil(beta9)
        XCTAssertNotNil(beta10)
        XCTAssertTrue(beta10! > beta9!)
    }

    func testInvalidVersionReturnsNil() {
        XCTAssertNil(AppVersion.parse("not-a-version"))
        XCTAssertNil(AppVersion.parse("0.1"))
        XCTAssertNil(AppVersion.parse("0.1.0-beta.x"))
    }
}
