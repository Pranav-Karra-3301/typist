import XCTest
@testable import TypistCore

final class MetricsEngineDiagnosticsTests: XCTestCase {
    func testDiagnosticsReflectIngestedEvents() async throws {
        let store = MockStoreForDiagnostics()
        let engine = MetricsEngine(store: store, queryService: store, flushInterval: .seconds(60), flushThreshold: 100)

        await engine.start()
        let now = Date()
        await engine.ingest(KeyEvent(timestamp: now, keyCode: 4, isSeparator: false, deviceClass: .builtIn))

        let diagnostics = await engine.diagnostics()
        XCTAssertTrue(diagnostics.isStarted)
        XCTAssertEqual(diagnostics.totalIngestedEvents, 1)
        XCTAssertEqual(diagnostics.pendingEvents, 1)
    }
}

private actor MockStoreForDiagnostics: TypistStore {
    func flush(
        events: [KeyEvent],
        wordIncrements: [WordIncrement],
        activeTypingIncrements: [ActiveTypingIncrement],
        sessionData: [SessionFlushData]
    ) async throws {}

    func snapshot(for timeframe: Timeframe, now: Date) async throws -> StatsSnapshot {
        StatsSnapshot.empty(timeframe: timeframe)
    }

    func resetAllData() async throws {}
}
