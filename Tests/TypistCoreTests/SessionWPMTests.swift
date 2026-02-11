import XCTest
@testable import TypistCore

final class SessionWPMTests: XCTestCase {
    private let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
    private let baseMonotonic: TimeInterval = 1000.0

    // MARK: - Helpers

    private func makeEngine(
        store: MockStoreForSession,
        sessionConfig: SessionConfig = .default,
        flushThreshold: Int = 1000
    ) -> MetricsEngine {
        MetricsEngine(
            store: store,
            queryService: store,
            flushInterval: .seconds(300),
            flushThreshold: flushThreshold,
            sessionConfig: sessionConfig
        )
    }

    private func letterEvent(
        keyCode: Int = 4,
        at wallOffset: TimeInterval,
        monotonicOffset: TimeInterval,
        appBundleID: String = "com.test.app",
        appName: String = "TestApp"
    ) -> KeyEvent {
        KeyEvent(
            timestamp: baseTime.addingTimeInterval(wallOffset),
            keyCode: keyCode,
            isSeparator: false,
            deviceClass: .builtIn,
            appBundleID: appBundleID,
            appName: appName,
            monotonicTime: baseMonotonic + monotonicOffset
        )
    }

    private func separatorEvent(
        keyCode: Int = 44,
        at wallOffset: TimeInterval,
        monotonicOffset: TimeInterval,
        appBundleID: String = "com.test.app",
        appName: String = "TestApp"
    ) -> KeyEvent {
        KeyEvent(
            timestamp: baseTime.addingTimeInterval(wallOffset),
            keyCode: keyCode,
            isSeparator: true,
            deviceClass: .builtIn,
            appBundleID: appBundleID,
            appName: appName,
            monotonicTime: baseMonotonic + monotonicOffset
        )
    }

    private func deleteEvent(
        at wallOffset: TimeInterval,
        monotonicOffset: TimeInterval,
        appBundleID: String = "com.test.app",
        appName: String = "TestApp"
    ) -> KeyEvent {
        KeyEvent(
            timestamp: baseTime.addingTimeInterval(wallOffset),
            keyCode: 42, // Backspace
            isSeparator: false,
            deviceClass: .builtIn,
            appBundleID: appBundleID,
            appName: appName,
            monotonicTime: baseMonotonic + monotonicOffset
        )
    }

    // MARK: - Tests

    /// Type a few letters quickly, wait 10s (monotonic), then press space.
    /// Flow WPM should reflect ~11s for 1 word.
    func testMidWordPauseThenSeparator() async throws {
        let store = MockStoreForSession()
        let engine = makeEngine(store: store)

        await engine.start()

        // Type "hel" quickly at t=0, t=0.2, t=0.4
        await engine.ingest(letterEvent(keyCode: 11, at: 0, monotonicOffset: 0))       // h
        await engine.ingest(letterEvent(keyCode: 8, at: 0.2, monotonicOffset: 0.2))     // e
        await engine.ingest(letterEvent(keyCode: 15, at: 0.4, monotonicOffset: 0.4))    // l

        // Wait 10s then type "lo" + space
        await engine.ingest(letterEvent(keyCode: 15, at: 10.4, monotonicOffset: 10.4))  // l
        await engine.ingest(letterEvent(keyCode: 18, at: 10.6, monotonicOffset: 10.6))  // o
        await engine.ingest(separatorEvent(at: 10.8, monotonicOffset: 10.8))             // space

        let snapshot = try await engine.snapshot(for: .h1, now: baseTime.addingTimeInterval(12))

        // 1 word committed via separator
        XCTAssertEqual(snapshot.totalWords, 1)

        // Flow time: the 10s gap is capped at idleCapFlow (12s), so the full gap counts.
        // Approximate total flow: 0.2 + 0.2 + 10.0 + 0.2 + 0.2 = ~10.8s
        XCTAssertGreaterThan(snapshot.activeSecondsFlow, 10.0)
        XCTAssertLessThan(snapshot.activeSecondsFlow, 12.0)
    }

    /// "hello " wait 10s "world " -> 2 words in ~12s flow time.
    func testPauseAfterSeparator() async throws {
        let store = MockStoreForSession()
        let engine = makeEngine(store: store)

        await engine.start()

        // "hello " at t=0..1.0
        await engine.ingest(letterEvent(keyCode: 11, at: 0, monotonicOffset: 0))
        await engine.ingest(letterEvent(keyCode: 8, at: 0.2, monotonicOffset: 0.2))
        await engine.ingest(letterEvent(keyCode: 15, at: 0.4, monotonicOffset: 0.4))
        await engine.ingest(letterEvent(keyCode: 15, at: 0.6, monotonicOffset: 0.6))
        await engine.ingest(letterEvent(keyCode: 18, at: 0.8, monotonicOffset: 0.8))
        await engine.ingest(separatorEvent(at: 1.0, monotonicOffset: 1.0))

        // Wait 10s, then "world "
        await engine.ingest(letterEvent(keyCode: 26, at: 11.0, monotonicOffset: 11.0))
        await engine.ingest(letterEvent(keyCode: 18, at: 11.2, monotonicOffset: 11.2))
        await engine.ingest(letterEvent(keyCode: 21, at: 11.4, monotonicOffset: 11.4))
        await engine.ingest(letterEvent(keyCode: 15, at: 11.6, monotonicOffset: 11.6))
        await engine.ingest(letterEvent(keyCode: 7, at: 11.8, monotonicOffset: 11.8))
        await engine.ingest(separatorEvent(at: 12.0, monotonicOffset: 12.0))

        let snapshot = try await engine.snapshot(for: .h1, now: baseTime.addingTimeInterval(14))

        XCTAssertEqual(snapshot.totalWords, 2)

        // Flow time includes the 10s gap (capped at 12s) plus letter deltas
        XCTAssertGreaterThan(snapshot.activeSecondsFlow, 11.0)
    }

    /// "hello" + space + space + space + "world" + space -> 2 words, not 4.
    func testHoldSpaceWordCountIsCorrect() async throws {
        let store = MockStoreForSession()
        let engine = makeEngine(store: store)

        await engine.start()

        // "hello"
        await engine.ingest(letterEvent(keyCode: 11, at: 0, monotonicOffset: 0))
        await engine.ingest(letterEvent(keyCode: 8, at: 0.2, monotonicOffset: 0.2))
        await engine.ingest(letterEvent(keyCode: 15, at: 0.4, monotonicOffset: 0.4))
        await engine.ingest(letterEvent(keyCode: 15, at: 0.6, monotonicOffset: 0.6))
        await engine.ingest(letterEvent(keyCode: 18, at: 0.8, monotonicOffset: 0.8))

        // space x3
        await engine.ingest(separatorEvent(at: 1.0, monotonicOffset: 1.0))
        await engine.ingest(separatorEvent(at: 1.1, monotonicOffset: 1.1))
        await engine.ingest(separatorEvent(at: 1.2, monotonicOffset: 1.2))

        // "world"
        await engine.ingest(letterEvent(keyCode: 26, at: 1.4, monotonicOffset: 1.4))
        await engine.ingest(letterEvent(keyCode: 18, at: 1.6, monotonicOffset: 1.6))
        await engine.ingest(letterEvent(keyCode: 21, at: 1.8, monotonicOffset: 1.8))
        await engine.ingest(letterEvent(keyCode: 15, at: 2.0, monotonicOffset: 2.0))
        await engine.ingest(letterEvent(keyCode: 7, at: 2.2, monotonicOffset: 2.2))

        // final space
        await engine.ingest(separatorEvent(at: 2.4, monotonicOffset: 2.4))

        let snapshot = try await engine.snapshot(for: .h1, now: baseTime.addingTimeInterval(4))

        XCTAssertEqual(snapshot.totalWords, 2)
    }

    /// Type a letter + backspace -> editEvents increments.
    func testDeleteCountsAsEditEvent() async throws {
        let store = MockStoreForSession()
        let engine = makeEngine(store: store)

        await engine.start()

        await engine.ingest(letterEvent(keyCode: 4, at: 0, monotonicOffset: 0))
        await engine.ingest(deleteEvent(at: 0.5, monotonicOffset: 0.5))

        let snapshot = try await engine.snapshot(for: .h1, now: baseTime.addingTimeInterval(2))

        XCTAssertEqual(snapshot.editEvents, 1)
    }

    /// Type "hello" without trailing space, then stop engine -> words should be 1 after session flush.
    func testNoTrailingSpaceCountsLastWord() async throws {
        let store = MockStoreForSession()
        let engine = makeEngine(store: store)

        await engine.start()

        // Type "hello" without space
        await engine.ingest(letterEvent(keyCode: 11, at: 0, monotonicOffset: 0))
        await engine.ingest(letterEvent(keyCode: 8, at: 0.2, monotonicOffset: 0.2))
        await engine.ingest(letterEvent(keyCode: 15, at: 0.4, monotonicOffset: 0.4))
        await engine.ingest(letterEvent(keyCode: 15, at: 0.6, monotonicOffset: 0.6))
        await engine.ingest(letterEvent(keyCode: 18, at: 0.8, monotonicOffset: 0.8))

        // Before stopping, no words should be committed yet (no separator pressed)
        let beforeStop = try await engine.snapshot(for: .h1, now: baseTime.addingTimeInterval(2))
        XCTAssertEqual(beforeStop.totalWords, 0)

        // Stop engine — endAllSessions flushes the last in-progress word
        await engine.stop()

        // After stop, the store should have received the flushed last word.
        // The engine flushes both per-app and global word counters on session end,
        // but only the per-app flush appends a WordIncrement.
        let flushedWords = await store.flushedWordIncrementCount
        XCTAssertGreaterThanOrEqual(flushedWords, 1, "At least 1 word should be flushed on engine stop")
    }

    /// Events 61s apart (monotonic) should be in different sessions.
    func testSessionTimeoutCreatesNewSession() async throws {
        let store = MockStoreForSession()
        let config = SessionConfig(sessionTimeout: 60, idleCapFlow: 12, idleCapSkill: 2)
        let engine = makeEngine(store: store, sessionConfig: config)

        await engine.start()

        // First word: "hi " at t=0
        await engine.ingest(letterEvent(keyCode: 11, at: 0, monotonicOffset: 0))
        await engine.ingest(letterEvent(keyCode: 12, at: 0.2, monotonicOffset: 0.2))
        await engine.ingest(separatorEvent(at: 0.4, monotonicOffset: 0.4))

        // Wait 61s (exceeds sessionTimeout of 60s), then type "ok "
        await engine.ingest(letterEvent(keyCode: 18, at: 61.4, monotonicOffset: 61.4))
        await engine.ingest(letterEvent(keyCode: 14, at: 61.6, monotonicOffset: 61.6))
        await engine.ingest(separatorEvent(at: 61.8, monotonicOffset: 61.8))

        let snapshot = try await engine.snapshot(for: .h1, now: baseTime.addingTimeInterval(65))

        // 2 words total but flow time should NOT include the 61s gap as continuous active time.
        // The session timeout causes a session break.
        // First session: ~0.4s flow, second session: ~0.4s flow.
        // The old session's last word ("hi") was already committed via separator,
        // so ending it doesn't add another word.
        XCTAssertEqual(snapshot.totalWords, 2)

        // Flow time should be much less than 61s because the timeout breaks the session.
        // First session contributes ~0.4s, second session contributes ~0.4s.
        XCTAssertLessThan(snapshot.activeSecondsFlow, 5.0)
    }

    /// Events 5s apart -> flow gets min(5, 12) = 5s, skill gets min(5, 2) = 2s.
    func testFlowVsSkillTimingDifference() async throws {
        let store = MockStoreForSession()
        let config = SessionConfig(sessionTimeout: 60, idleCapFlow: 12, idleCapSkill: 2)
        let engine = makeEngine(store: store, sessionConfig: config)

        await engine.start()

        // Two text-producing events 5s apart
        await engine.ingest(letterEvent(keyCode: 4, at: 0, monotonicOffset: 0))
        await engine.ingest(letterEvent(keyCode: 5, at: 5.0, monotonicOffset: 5.0))

        let snapshot = try await engine.snapshot(for: .h1, now: baseTime.addingTimeInterval(7))

        // Flow: min(5, 12) = 5.0s
        XCTAssertEqual(snapshot.activeSecondsFlow, 5.0, accuracy: 0.01)

        // Skill: min(5, 2) = 2.0s
        XCTAssertEqual(snapshot.activeSecondsSkill, 2.0, accuracy: 0.01)
    }
}

// MARK: - MockStore for Session Tests

private actor MockStoreForSession: TypistStore {
    private(set) var flushedEventCount = 0
    private(set) var flushedWordIncrementCount = 0

    func flush(
        events: [KeyEvent],
        wordIncrements: [WordIncrement],
        activeTypingIncrements: [ActiveTypingIncrement],
        sessionData: [SessionFlushData]
    ) async throws {
        flushedEventCount += events.count
        flushedWordIncrementCount += wordIncrements.count
    }

    func snapshot(for timeframe: Timeframe, now: Date) async throws -> StatsSnapshot {
        StatsSnapshot.empty(timeframe: timeframe)
    }

    func resetAllData() async throws {
        flushedEventCount = 0
        flushedWordIncrementCount = 0
    }
}
