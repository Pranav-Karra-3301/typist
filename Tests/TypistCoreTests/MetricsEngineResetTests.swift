import XCTest
@testable import TypistCore

final class MetricsEngineResetTests: XCTestCase {
    func testResetInMemoryStateClearsPendingData() async throws {
        let store = MockStoreForReset()
        let engine = MetricsEngine(store: store, queryService: store, flushInterval: .seconds(60), flushThreshold: 200)

        await engine.start()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        await engine.ingest(KeyEvent(timestamp: baseTime, keyCode: 4, isSeparator: false, deviceClass: .builtIn))
        await engine.ingest(KeyEvent(timestamp: baseTime.addingTimeInterval(1), keyCode: 44, isSeparator: true, deviceClass: .builtIn))

        let beforeReset = try await engine.snapshot(for: .h24, now: baseTime.addingTimeInterval(2))
        XCTAssertEqual(beforeReset.totalKeystrokes, 2)
        XCTAssertEqual(beforeReset.totalWords, 1)

        await engine.resetInMemoryState()

        let afterReset = try await engine.snapshot(for: .h24, now: baseTime.addingTimeInterval(3))
        XCTAssertEqual(afterReset.totalKeystrokes, 0)
        XCTAssertEqual(afterReset.totalWords, 0)
    }
}

private actor MockStoreForReset: TypistStore {
    func flush(
        events: [KeyEvent],
        wordIncrements: [WordIncrement],
        activeTypingIncrements: [ActiveTypingIncrement]
    ) async throws {}

    func snapshot(for timeframe: Timeframe, now: Date) async throws -> StatsSnapshot {
        StatsSnapshot.empty(timeframe: timeframe)
    }

    func resetAllData() async throws {}
}
