import XCTest
@testable import TypistCore

final class TimeframeTests: XCTestCase {
    func testTrendGranularitySelection() {
        XCTAssertEqual(Timeframe.h1.trendGranularity, .fiveMinutes)
        XCTAssertEqual(Timeframe.h12.trendGranularity, .hour)
        XCTAssertEqual(Timeframe.h24.trendGranularity, .hour)
        XCTAssertEqual(Timeframe.d7.trendGranularity, .day)
        XCTAssertEqual(Timeframe.d30.trendGranularity, .day)
        XCTAssertEqual(Timeframe.all.trendGranularity, .day)
    }

    func testStartDateFor1Hour() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let start = Timeframe.h1.startDate(now: now, calendar: calendar)
        XCTAssertNotNil(start)

        if let start {
            let delta = now.timeIntervalSince(start)
            XCTAssertEqual(delta, 3600, accuracy: 1)
        }
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

    func testStartOfFiveMinutesRoundsDown() {
        let calendar = Calendar(identifier: .gregorian)
        let date = Date(timeIntervalSince1970: 1_700_000_123) // minute/second not aligned
        let rounded = TimeBucket.start(of: date, granularity: .fiveMinutes, calendar: calendar)
        let components = calendar.dateComponents([.minute, .second], from: rounded)
        XCTAssertEqual((components.minute ?? 0) % 5, 0)
        XCTAssertEqual(components.second, 0)
        XCTAssertLessThanOrEqual(rounded, date)
    }

    func testAdvanceFiveMinutes() {
        let calendar = Calendar(identifier: .gregorian)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let advanced = TimeBucket.advance(base, by: .fiveMinutes, calendar: calendar)
        XCTAssertEqual(advanced.timeIntervalSince(base), 300, accuracy: 0.5)
    }

    func testAllTimeHasNoStartDate() {
        XCTAssertNil(Timeframe.all.startDate(now: Date()))
    }
}
