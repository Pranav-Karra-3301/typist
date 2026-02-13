import XCTest
@testable import TypistCore

final class MetricsEngineTests: XCTestCase {
    private func databaseURL(for testName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("typist-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(testName).sqlite3")
    }

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

    func testNonTextProducingKeysDoNotAffectWordCounts() async throws {
        let store = MockStore()
        let engine = MetricsEngine(store: store, queryService: store, flushInterval: .seconds(60), flushThreshold: 200)

        await engine.start()

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let events = [
            KeyEvent(
                timestamp: now,
                keyCode: 4,
                isSeparator: false,
                deviceClass: .builtIn,
                monotonicTime: 1
            ),
            KeyEvent(
                timestamp: now + 1,
                keyCode: 44,
                isSeparator: true,
                deviceClass: .builtIn,
                monotonicTime: 2
            ),
            KeyEvent(
                timestamp: now + 2,
                keyCode: 79,
                isSeparator: false,
                deviceClass: .builtIn,
                monotonicTime: 3,
                isTextProducing: false
            )
        ]

        for event in events {
            await engine.ingest(event)
        }

        let snapshot = try await engine.snapshot(for: .h1, now: now + 3)

        XCTAssertEqual(snapshot.totalKeystrokes, 3)
        XCTAssertEqual(snapshot.totalWords, 1)
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

    func testPendingEventsAreFilteredByCurrentTimeInSnapshot() async throws {
        let store = MockStore()
        let engine = MetricsEngine(store: store, queryService: store, flushInterval: .seconds(60), flushThreshold: 200)

        await engine.start()

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let pastWord = [
            KeyEvent(timestamp: now - 20 * 60, keyCode: 4, isSeparator: false, deviceClass: .builtIn, monotonicTime: 100),
            KeyEvent(timestamp: now - 20 * 60 + 1, keyCode: 44, isSeparator: true, deviceClass: .builtIn, monotonicTime: 101)
        ]
        let futureWord = [
            KeyEvent(timestamp: now + 15 * 60, keyCode: 5, isSeparator: false, deviceClass: .builtIn, monotonicTime: 1_000),
            KeyEvent(timestamp: now + 15 * 60 + 1, keyCode: 44, isSeparator: true, deviceClass: .builtIn, monotonicTime: 1_001)
        ]

        for event in pastWord + futureWord {
            await engine.ingest(event)
        }

        let snapshot = try await engine.snapshot(for: .h1, now: now)

        XCTAssertEqual(snapshot.totalKeystrokes, 2)
        XCTAssertEqual(snapshot.totalWords, 1)
        XCTAssertEqual(snapshot.typedWords, 1)
        XCTAssertLessThan(snapshot.activeSecondsFlow, 1.01)
        XCTAssertGreaterThan(snapshot.activeSecondsFlow, 0.99)
    }

    func testOneHourSnapshotUsesMultipleWordBuckets() async throws {
        let store = MockStore()
        let engine = MetricsEngine(
            store: store,
            queryService: store,
            flushInterval: .seconds(60),
            flushThreshold: 200
        )

        await engine.start()

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let minute = 60.0
        let baseMonotonic = 1_000.0

        func ingestWordBatch(startOffset: TimeInterval, monotonicOffset: TimeInterval, words: Int, lettersPerWord: Int = 4) async {
            let wordEventSpan = Double(lettersPerWord + 1) * 0.6
            var currentOffset = startOffset
            var currentMonotonic = monotonicOffset

            for _ in 0..<words {
                for _ in 0..<lettersPerWord {
                    await engine.ingest(
                        KeyEvent(
                            timestamp: now.addingTimeInterval(currentOffset),
                            keyCode: 4,
                            isSeparator: false,
                            deviceClass: .builtIn,
                            monotonicTime: baseMonotonic + currentMonotonic
                        )
                    )
                    currentOffset += 0.6
                    currentMonotonic += 0.6
                }
                await engine.ingest(
                    KeyEvent(
                        timestamp: now.addingTimeInterval(currentOffset),
                        keyCode: 44,
                        isSeparator: true,
                        deviceClass: .builtIn,
                        monotonicTime: baseMonotonic + currentMonotonic
                    )
                )
                currentOffset += wordEventSpan
                currentMonotonic += wordEventSpan
            }
        }

        await ingestWordBatch(startOffset: -55 * minute, monotonicOffset: 0, words: 1)
        await ingestWordBatch(startOffset: -35 * minute, monotonicOffset: 600, words: 3)
        await ingestWordBatch(startOffset: -15 * minute, monotonicOffset: 1300, words: 2)

        let snapshot = try await engine.snapshot(for: .h1, now: now)

        let wordBuckets = snapshot.typingSpeedTrendSeries.filter { $0.words > 0 }
        XCTAssertEqual(snapshot.totalWords, 6)
        XCTAssertEqual(snapshot.typedWords, 6)
        XCTAssertEqual(wordBuckets.count, 3)
        XCTAssertEqual(wordBuckets.map(\.words), [1, 3, 2])
    }

    func testOneHourTypingSpeedTrendVariesWithTypingPace() async throws {
        let store = MockStore()
        let engine = MetricsEngine(
            store: store,
            queryService: store,
            flushInterval: .seconds(60),
            flushThreshold: 200
        )

        await engine.start()

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let minute = 60.0
        let baseMonotonic = 2_000.0

        func ingestWordBatch(
            startOffset: TimeInterval,
            monotonicOffset: TimeInterval,
            words: Int,
            letters: Int,
            charInterval: TimeInterval
        ) async {
            let wordEventSpan = Double(letters + 1) * charInterval
            var currentOffset = startOffset
            var currentMonotonic = monotonicOffset

            for _ in 0..<words {
                for _ in 0..<letters {
                    await engine.ingest(
                        KeyEvent(
                            timestamp: now.addingTimeInterval(currentOffset),
                            keyCode: 4,
                            isSeparator: false,
                            deviceClass: .builtIn,
                            monotonicTime: baseMonotonic + currentMonotonic
                        )
                    )
                    currentOffset += charInterval
                    currentMonotonic += charInterval
                }
                await engine.ingest(
                    KeyEvent(
                        timestamp: now.addingTimeInterval(currentOffset),
                        keyCode: 44,
                        isSeparator: true,
                        deviceClass: .builtIn,
                        monotonicTime: baseMonotonic + currentMonotonic
                    )
                )

                currentOffset += wordEventSpan
                currentMonotonic += wordEventSpan
            }
        }

        await ingestWordBatch(
            startOffset: -55 * minute,
            monotonicOffset: 0,
            words: 4,
            letters: 4,
            charInterval: 0.08
        )
        await ingestWordBatch(
            startOffset: -25 * minute,
            monotonicOffset: 500,
            words: 4,
            letters: 4,
            charInterval: 1.2
        )
        await ingestWordBatch(
            startOffset: -5 * minute,
            monotonicOffset: 1200,
            words: 1,
            letters: 4,
            charInterval: 0.08
        )

        let snapshot = try await engine.snapshot(for: .h1, now: now)
        let paceBuckets = snapshot.typingSpeedTrendSeries.filter { $0.words > 0 }

        XCTAssertEqual(paceBuckets.count, 3)
        XCTAssertNotEqual(paceBuckets[0].flowWPM, paceBuckets[1].flowWPM)
        XCTAssertNotEqual(paceBuckets[1].flowWPM, paceBuckets[2].flowWPM)
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

    func testSuppressedDictationSourcesIncludeSystemBundleAndAppNameVariants() async throws {
        let store = MockStore()
        let engine = MetricsEngine(store: store, queryService: store, flushInterval: .seconds(60), flushThreshold: 200)

        await engine.start()

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cases = [
            ("com.apple.speechrecognition", "SpeechRecognition"),
            ("com.apple.speech.voiceinput", "Apple Voice Input"),
            ("com.apple.kotoeri", "Kotoeri"),
            ("com.superwispr", "Wispr dictation")
        ]

        for (index, suppressedCase) in cases.enumerated() {
            let base = now - Double(index * 4)
            let keyDown = KeyEvent(
                timestamp: base,
                keyCode: 4,
                isSeparator: false,
                deviceClass: .builtIn,
                appBundleID: suppressedCase.0,
                appName: suppressedCase.1,
                monotonicTime: TimeInterval(index * 2),
                isTextProducing: true
            )
            let separator = KeyEvent(
                timestamp: base + 1,
                keyCode: 44,
                isSeparator: true,
                deviceClass: .builtIn,
                appBundleID: suppressedCase.0,
                appName: suppressedCase.1,
                monotonicTime: TimeInterval(index * 2 + 1),
                isTextProducing: true
            )

            await engine.ingest(keyDown)
            await engine.ingest(separator)
        }

        let normal = KeyEvent(
            timestamp: now,
            keyCode: 4,
            isSeparator: false,
            deviceClass: .builtIn,
            appBundleID: "com.apple.TextEdit",
            appName: "TextEdit",
            monotonicTime: 100,
            isTextProducing: true
        )
        let normalSeparator = KeyEvent(
            timestamp: now + 1,
            keyCode: 44,
            isSeparator: true,
            deviceClass: .builtIn,
            appBundleID: "com.apple.TextEdit",
            appName: "TextEdit",
            monotonicTime: 101,
            isTextProducing: true
        )
        await engine.ingest(normal)
        await engine.ingest(normalSeparator)

        let snapshot = try await engine.snapshot(for: .h1, now: now + 2)

        XCTAssertEqual(snapshot.totalWords, 1)
        XCTAssertEqual(snapshot.totalKeystrokes, 10)
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

        let snapshot = try await engine.snapshot(for: .h1, now: now + 12)

        XCTAssertEqual(snapshot.totalKeystrokes, 13)
        XCTAssertEqual(snapshot.totalWords, 0)
        XCTAssertEqual(snapshot.typedWords, 0)
        XCTAssertEqual(snapshot.activeSecondsFlow, 0)
    }

    func testOneHourSnapshotCombinesStoreAndPendingData() async throws {
        let dbURL = try databaseURL(for: #function)
        let store = try SQLiteStore(databaseURL: dbURL, retentionDays: 10_000)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let persistedBase = now.addingTimeInterval(-30 * 60)

        let persistedEvents = [
            KeyEvent(timestamp: persistedBase, keyCode: 4, isSeparator: false, deviceClass: .builtIn, monotonicTime: 10),
            KeyEvent(timestamp: persistedBase + 1, keyCode: 44, isSeparator: true, deviceClass: .builtIn, monotonicTime: 11)
        ]
        try await store.flush(
            events: persistedEvents,
            wordIncrements: [WordIncrement(timestamp: persistedBase + 1, deviceClass: .builtIn)],
            activeTypingIncrements: [ActiveTypingIncrement(
                bucketStart: persistedBase,
                activeSeconds: 1,
                activeSecondsFlow: 1,
                activeSecondsSkill: 1
            )]
        )

        let engine = MetricsEngine(
            store: store,
            queryService: store,
            flushInterval: .seconds(60),
            flushThreshold: 200
        )
        await engine.start()

        let pendingEvents = [
            KeyEvent(timestamp: now - 20, keyCode: 5, isSeparator: false, deviceClass: .builtIn, monotonicTime: 20),
            KeyEvent(timestamp: now - 19, keyCode: 44, isSeparator: true, deviceClass: .builtIn, monotonicTime: 21)
        ]
        for event in pendingEvents {
            await engine.ingest(event)
        }

        let snapshot = try await engine.snapshot(for: .h1, now: now)

        XCTAssertEqual(snapshot.totalKeystrokes, 4)
        XCTAssertEqual(snapshot.totalWords, 2)
        XCTAssertEqual(snapshot.typedWords, 2)
        XCTAssertGreaterThan(snapshot.typingSpeedTrendSeries.filter { $0.words > 0 }.count, 0)
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
