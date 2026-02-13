import XCTest
@testable import TypistCore

final class MetricsEngineTests: XCTestCase {
    func testSnapshotIncludesPendingEventsBeforeFlush() async throws {
        let store = MockStore()
        let engine = MetricsEngine(store: store, queryService: store, flushInterval: .seconds(60), flushThreshold: 200)

        await engine.start()

        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let events = [
            KeyEvent(timestamp: baseTime, keyCode: 4, isSeparator: false, deviceClass: .builtIn),
            KeyEvent(timestamp: baseTime.addingTimeInterval(1), keyCode: 44, isSeparator: true, deviceClass: .builtIn),
            KeyEvent(timestamp: baseTime.addingTimeInterval(2), keyCode: 5, isSeparator: false, deviceClass: .external),
            KeyEvent(timestamp: baseTime.addingTimeInterval(3), keyCode: 44, isSeparator: true, deviceClass: .external)
        ]

        for event in events {
            await engine.ingest(event)
        }

        let snapshot = try await engine.snapshot(for: .h24, now: baseTime.addingTimeInterval(4))

        XCTAssertEqual(snapshot.totalKeystrokes, 4)
        XCTAssertEqual(snapshot.totalWords, 2)
        XCTAssertEqual(snapshot.deviceBreakdown.builtIn, 2)
        XCTAssertEqual(snapshot.deviceBreakdown.external, 2)
        XCTAssertEqual(snapshot.keyDistribution.first?.keyCode, 44)
        XCTAssertEqual(snapshot.keyDistribution.first?.count, 2)
    }

    func testFlushTriggeredAtThreshold() async throws {
        let store = MockStore()
        let engine = MetricsEngine(store: store, queryService: store, flushInterval: .seconds(60), flushThreshold: 2)

        await engine.start()

        let now = Date()
        await engine.ingest(KeyEvent(timestamp: now, keyCode: 4, isSeparator: false, deviceClass: .builtIn))
        await engine.ingest(KeyEvent(timestamp: now, keyCode: 44, isSeparator: true, deviceClass: .builtIn))

        let flushedEvents = await store.flushedEventCount
        XCTAssertEqual(flushedEvents, 2)
    }

    func testSnapshotChangesCountsAndTopKeysByTimeframe() async throws {
        let store = MockStore()
        let engine = MetricsEngine(store: store, queryService: store, flushInterval: .seconds(60), flushThreshold: 200)

        await engine.start()

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let events = [
            KeyEvent(timestamp: now.addingTimeInterval(-26 * 3600), keyCode: 4, isSeparator: false, deviceClass: .builtIn),
            KeyEvent(timestamp: now.addingTimeInterval(-26 * 3600 + 1), keyCode: 4, isSeparator: false, deviceClass: .builtIn),
            KeyEvent(timestamp: now.addingTimeInterval(-40 * 60), keyCode: 5, isSeparator: false, deviceClass: .builtIn),
            KeyEvent(timestamp: now.addingTimeInterval(-30 * 60), keyCode: 5, isSeparator: false, deviceClass: .builtIn),
            KeyEvent(timestamp: now.addingTimeInterval(-20 * 60), keyCode: 6, isSeparator: false, deviceClass: .builtIn)
        ]

        for event in events {
            await engine.ingest(event)
        }

        let oneHour = try await engine.snapshot(for: .h1, now: now)
        XCTAssertEqual(oneHour.totalKeystrokes, 3)
        XCTAssertEqual(oneHour.topKeys.first?.keyCode, 5)
        XCTAssertEqual(oneHour.topKeys.first?.count, 2)

        let sevenDays = try await engine.snapshot(for: .d7, now: now)
        XCTAssertEqual(sevenDays.totalKeystrokes, 5)
        XCTAssertEqual(sevenDays.topKeys.first?.keyCode, 4)
        XCTAssertEqual(sevenDays.topKeys.first?.count, 2)
    }

    func testSnapshotIncludesPendingWPMAndTopApps() async throws {
        let store = MockStore()
        let engine = MetricsEngine(store: store, queryService: store, flushInterval: .seconds(60), flushThreshold: 200)

        await engine.start()

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let events = [
            KeyEvent(
                timestamp: now.addingTimeInterval(-50),
                keyCode: 4,
                isSeparator: false,
                deviceClass: .builtIn,
                appBundleID: "com.apple.TextEdit",
                appName: "TextEdit"
            ),
            KeyEvent(
                timestamp: now.addingTimeInterval(-49),
                keyCode: 44,
                isSeparator: true,
                deviceClass: .builtIn,
                appBundleID: "com.apple.TextEdit",
                appName: "TextEdit"
            ),
            KeyEvent(
                timestamp: now.addingTimeInterval(-20),
                keyCode: 5,
                isSeparator: false,
                deviceClass: .builtIn,
                appBundleID: "com.apple.dt.Xcode",
                appName: "Xcode"
            ),
            KeyEvent(
                timestamp: now.addingTimeInterval(-19),
                keyCode: 44,
                isSeparator: true,
                deviceClass: .builtIn,
                appBundleID: "com.apple.dt.Xcode",
                appName: "Xcode"
            )
        ]

        for event in events {
            await engine.ingest(event)
        }

        let snapshot = try await engine.snapshot(for: .h1, now: now)

        XCTAssertEqual(snapshot.totalWords, 2)
        XCTAssertEqual(snapshot.typedWords, 2)
        XCTAssertEqual(snapshot.topAppsByWords.count, 2)
        XCTAssertEqual(snapshot.topAppsByWords.first?.wordCount, 1)
        XCTAssertEqual(snapshot.wpmTrendSeries.reduce(0) { $0 + $1.words }, 2)
    }

    func testOneHourSnapshotUsesFiveMinuteWordBuckets() async throws {
        let store = MockStore()
        let engine = MetricsEngine(store: store, queryService: store, flushInterval: .seconds(60), flushThreshold: 200)

        await engine.start()

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let events = [
            KeyEvent(timestamp: now.addingTimeInterval(-50 * 60), keyCode: 4, isSeparator: false, deviceClass: .builtIn, monotonicTime: 1),
            KeyEvent(timestamp: now.addingTimeInterval(-50 * 60 + 1), keyCode: 44, isSeparator: true, deviceClass: .builtIn, monotonicTime: 2),
            KeyEvent(timestamp: now.addingTimeInterval(-34 * 60), keyCode: 5, isSeparator: false, deviceClass: .builtIn, monotonicTime: 3),
            KeyEvent(timestamp: now.addingTimeInterval(-34 * 60 + 1), keyCode: 44, isSeparator: true, deviceClass: .builtIn, monotonicTime: 4),
            KeyEvent(timestamp: now.addingTimeInterval(-9 * 60), keyCode: 6, isSeparator: false, deviceClass: .builtIn, monotonicTime: 5),
            KeyEvent(timestamp: now.addingTimeInterval(-9 * 60 + 1), keyCode: 44, isSeparator: true, deviceClass: .builtIn, monotonicTime: 6)
        ]

        for event in events {
            await engine.ingest(event)
        }

        let snapshot = try await engine.snapshot(for: .h1, now: now)
        let nonZeroWordBuckets = snapshot.wpmTrendSeries.filter { $0.words > 0 }

        XCTAssertEqual(snapshot.totalWords, 3)
        XCTAssertEqual(snapshot.typedWords, 3)
        XCTAssertEqual(nonZeroWordBuckets.count, 3)
    }

    func testSuppressedSourcesDoNotCountWords() async throws {
        let store = MockStore()
        let engine = MetricsEngine(store: store, queryService: store, flushInterval: .seconds(60), flushThreshold: 200)

        await engine.start()

        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let normalWord = [
            KeyEvent(timestamp: now - 25, keyCode: 4, isSeparator: false, deviceClass: .builtIn, appBundleID: "com.apple.TextEdit", appName: "TextEdit", monotonicTime: 0),
            KeyEvent(timestamp: now - 24, keyCode: 44, isSeparator: true, deviceClass: .builtIn, appBundleID: "com.apple.TextEdit", appName: "TextEdit", monotonicTime: 2)
        ]
        let dictationWord = [
            KeyEvent(timestamp: now - 15, keyCode: 4, isSeparator: false, deviceClass: .builtIn, appBundleID: "com.superwhisper.app", appName: "Super Whisper", monotonicTime: 4),
            KeyEvent(timestamp: now - 14, keyCode: 44, isSeparator: true, deviceClass: .builtIn, appBundleID: "com.superwhisper.app", appName: "Super Whisper", monotonicTime: 5)
        ]

        for event in normalWord + dictationWord {
            await engine.ingest(event)
        }

        let snapshot = try await engine.snapshot(for: .h1, now: now)

        XCTAssertEqual(snapshot.totalWords, 1)
        XCTAssertEqual(snapshot.totalKeystrokes, 4)
    }

    func testSuppressedSourcesMatchWhitespaceAndPunctuationVariants() async throws {
        let store = MockStore()
        let engine = MetricsEngine(store: store, queryService: store, flushInterval: .seconds(60), flushThreshold: 200)

        await engine.start()

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cases = [
            ("com.super-whisper.app", "Super-Whisper"),
            ("com.super_wisper.app", "SUPER WISPR"),
            ("com.voice input.dictation", "Voice Dictation (Beta)")
        ]

        for (offset, suppressedCase) in cases.enumerated() {
            let base = now - Double(offset * 4)
            let keyDown = KeyEvent(
                timestamp: base,
                keyCode: 4,
                isSeparator: false,
                deviceClass: .builtIn,
                appBundleID: suppressedCase.0,
                appName: suppressedCase.1,
                monotonicTime: TimeInterval(offset)
            )
            let separator = KeyEvent(
                timestamp: base + 1,
                keyCode: 44,
                isSeparator: true,
                deviceClass: .builtIn,
                appBundleID: suppressedCase.0,
                appName: suppressedCase.1,
                monotonicTime: TimeInterval(offset + 1)
            )
            await engine.ingest(keyDown)
            await engine.ingest(separator)
        }

        let normalKeystroke = KeyEvent(
            timestamp: now,
            keyCode: 4,
            isSeparator: false,
            deviceClass: .builtIn,
            appBundleID: "com.apple.TextEdit",
            appName: "TextEdit",
            monotonicTime: 100
        )
        let normalSeparator = KeyEvent(
            timestamp: now + 1,
            keyCode: 44,
            isSeparator: true,
            deviceClass: .builtIn,
            appBundleID: "com.apple.TextEdit",
            appName: "TextEdit",
            monotonicTime: 101
        )
        await engine.ingest(normalKeystroke)
        await engine.ingest(normalSeparator)

        let snapshot = try await engine.snapshot(for: .h1, now: now + 2)

        XCTAssertEqual(snapshot.totalKeystrokes, 8)
        XCTAssertEqual(snapshot.totalWords, 1)
        XCTAssertEqual(snapshot.typedWords, 1)
    }

    func testSuppressedDictationStreamDoesNotAffectWordOrFlowCounts() async throws {
        let store = MockStore()
        let engine = MetricsEngine(
            store: store,
            queryService: store,
            flushInterval: .seconds(60),
            flushThreshold: 200,
            sessionConfig: .init(sessionTimeout: 60, idleCapFlow: 12, idleCapSkill: 2)
        )

        await engine.start()

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<12 {
            let timestamp = now + Double(index)
            let keyEvent = KeyEvent(
                timestamp: timestamp,
                keyCode: 4,
                isSeparator: false,
                deviceClass: .builtIn,
                appBundleID: "com.superwhisper.app",
                appName: "Super Whisper",
                monotonicTime: 10 + Double(index),
                isTextProducing: true
            )
            await engine.ingest(keyEvent)
        }

        // Simulate voice dictation releasing key -> separator key from same app.
        let separator = KeyEvent(
            timestamp: now + 12,
            keyCode: 44,
            isSeparator: true,
            deviceClass: .builtIn,
            appBundleID: "com.superwhisper.app",
            appName: "Super Whisper",
            monotonicTime: 22,
            isTextProducing: true
        )
        await engine.ingest(separator)

        let snapshot = try await engine.snapshot(for: .h1, now: now + 2)

        XCTAssertEqual(snapshot.totalKeystrokes, 13)
        XCTAssertEqual(snapshot.totalWords, 0)
        XCTAssertEqual(snapshot.typedWords, 0)
        XCTAssertEqual(snapshot.activeSecondsFlow, 0)
    }

}

private actor MockStore: TypistStore {
    private(set) var flushedEventCount = 0

    func flush(
        events: [KeyEvent],
        wordIncrements: [WordIncrement],
        activeTypingIncrements: [ActiveTypingIncrement]
    ) async throws {
        flushedEventCount += events.count
    }

    func snapshot(for timeframe: Timeframe, now: Date) async throws -> StatsSnapshot {
        StatsSnapshot.empty(timeframe: timeframe)
    }

    func resetAllData() async throws {
        flushedEventCount = 0
    }
}
