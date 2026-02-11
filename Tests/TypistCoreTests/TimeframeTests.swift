import XCTest
@testable import TypistCore

final class TimeframeTests: XCTestCase {
    func testTrendGranularitySelection() {
        XCTAssertEqual(Timeframe.h12.trendGranularity, .hour)
        XCTAssertEqual(Timeframe.h24.trendGranularity, .hour)
        XCTAssertEqual(Timeframe.d7.trendGranularity, .day)
        XCTAssertEqual(Timeframe.d30.trendGranularity, .day)
        XCTAssertEqual(Timeframe.all.trendGranularity, .day)
    }

    func testStartDateFor12Hours() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let start = Timeframe.h12.startDate(now: now, calendar: calendar)
        XCTAssertNotNil(start)

        if let start {
            let delta = now.timeIntervalSince(start)
            XCTAssertEqual(delta, 12 * 3600, accuracy: 1)
        }
    }

    func testAllTimeHasNoStartDate() {
        XCTAssertNil(Timeframe.all.startDate(now: Date()))
    }
}
