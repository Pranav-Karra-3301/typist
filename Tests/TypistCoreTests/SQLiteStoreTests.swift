import Foundation
import XCTest
@testable import TypistCore

final class SQLiteStoreTests: XCTestCase {
    func testSnapshotReturnsCountsForKeysAndWords() async throws {
        let dbURL = makeDatabaseURL(testName: #function)
        let store = try SQLiteStore(databaseURL: dbURL, retentionDays: 10_000)

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let events: [KeyEvent] = [
            KeyEvent(timestamp: base, keyCode: 4, isSeparator: false, deviceClass: .builtIn),
            KeyEvent(timestamp: base.addingTimeInterval(1), keyCode: 44, isSeparator: true, deviceClass: .builtIn),
            KeyEvent(timestamp: base.addingTimeInterval(2), keyCode: 999_999, isSeparator: false, deviceClass: .builtIn)
        ]

        let words = [WordIncrement(timestamp: base.addingTimeInterval(1), deviceClass: .builtIn)]

        try await store.flush(events: events, wordIncrements: words, activeTypingIncrements: [])
        let snapshot = try await store.snapshot(for: .h24, now: base.addingTimeInterval(3))

        XCTAssertEqual(snapshot.totalKeystrokes, 2)
        XCTAssertEqual(snapshot.totalWords, 1)
        XCTAssertEqual(snapshot.deviceBreakdown.builtIn, 2)
        XCTAssertEqual(snapshot.keyDistribution.count, 2)
        XCTAssertEqual(snapshot.topKeys.count, 2)
        XCTAssertEqual(Set(snapshot.topKeys.map(\.keyCode)), Set([4, 44]))
    }

    func testSnapshotUsesStrictRollingTimeframeBoundaries() async throws {
        let dbURL = makeDatabaseURL(testName: #function)
        let store = try SQLiteStore(databaseURL: dbURL, retentionDays: 10_000)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let events: [KeyEvent] = [
            KeyEvent(timestamp: now.addingTimeInterval(-3_601), keyCode: 4, isSeparator: false, deviceClass: .builtIn),
            KeyEvent(timestamp: now.addingTimeInterval(-3_599), keyCode: 5, isSeparator: false, deviceClass: .builtIn),
            KeyEvent(timestamp: now.addingTimeInterval(-120), keyCode: 5, isSeparator: false, deviceClass: .builtIn),
            KeyEvent(timestamp: now.addingTimeInterval(-10), keyCode: 44, isSeparator: true, deviceClass: .builtIn)
        ]

        try await store.flush(events: events, wordIncrements: [], activeTypingIncrements: [])

        let oneHour = try await store.snapshot(for: .h1, now: now)
        XCTAssertEqual(oneHour.totalKeystrokes, 3)
        XCTAssertEqual(oneHour.topKeys.first?.keyCode, 5)
        XCTAssertEqual(oneHour.topKeys.first?.count, 2)

        let sevenDays = try await store.snapshot(for: .d7, now: now)
        XCTAssertEqual(sevenDays.totalKeystrokes, 4)
    }

    func testWordCountSkipsEventsMarkedAsIgnoredForWordStats() async throws {
        let dbURL = makeDatabaseURL(testName: #function)
        let store = try SQLiteStore(databaseURL: dbURL, retentionDays: 10_000)

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let events = [
            KeyEvent(
                timestamp: base,
                keyCode: 4,
                isSeparator: false,
                deviceClass: .builtIn,
                appBundleID: "com.apple.TextEdit",
                appName: "TextEdit"
            ),
            KeyEvent(
                timestamp: base.addingTimeInterval(1),
                keyCode: 44,
                isSeparator: true,
                deviceClass: .builtIn,
                appBundleID: "com.apple.TextEdit",
                appName: "TextEdit"
            ),
            KeyEvent(
                timestamp: base.addingTimeInterval(2),
                keyCode: 4,
                isSeparator: false,
                deviceClass: .builtIn,
                appBundleID: "com.superwhisper.app",
                appName: "Super Whisper",
                isCountedForWordStats: false
            ),
            KeyEvent(
                timestamp: base.addingTimeInterval(3),
                keyCode: 44,
                isSeparator: true,
                deviceClass: .builtIn,
                appBundleID: "com.superwhisper.app",
                appName: "Super Whisper",
                isCountedForWordStats: false
            )
        ]

        let wordIncrements = [
            WordIncrement(timestamp: base.addingTimeInterval(1), deviceClass: .builtIn)
        ]

        try await store.flush(events: events, wordIncrements: wordIncrements, activeTypingIncrements: [])
        let snapshot = try await store.snapshot(for: .h24, now: base.addingTimeInterval(10))

        XCTAssertEqual(snapshot.totalKeystrokes, 4)
        XCTAssertEqual(snapshot.totalWords, 1)
    }

    func testWordCountingInSnapshotUsesEventSequence() async throws {
        let dbURL = makeDatabaseURL(testName: #function)
        let store = try SQLiteStore(databaseURL: dbURL, retentionDays: 10_000)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let events: [KeyEvent] = [
            KeyEvent(timestamp: now.addingTimeInterval(-3_700), keyCode: 4, isSeparator: false, deviceClass: .builtIn),
            KeyEvent(timestamp: now.addingTimeInterval(-10), keyCode: 44, isSeparator: true, deviceClass: .builtIn)
        ]

        try await store.flush(events: events, wordIncrements: [], activeTypingIncrements: [])

        let oneHour = try await store.snapshot(for: .h1, now: now)
        XCTAssertEqual(oneHour.totalWords, 1)
    }

    func testSnapshotBoundsExcludesFutureRowsInOneHourWindow() async throws {
        let dbURL = makeDatabaseURL(testName: #function)
        let store = try SQLiteStore(databaseURL: dbURL, retentionDays: 10_000)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let events: [KeyEvent] = [
            KeyEvent(timestamp: now.addingTimeInterval(-50 * 60), keyCode: 4, isSeparator: false, deviceClass: .builtIn),
            KeyEvent(timestamp: now.addingTimeInterval(-49 * 60), keyCode: 44, isSeparator: true, deviceClass: .builtIn),
            KeyEvent(timestamp: now.addingTimeInterval(10 * 60), keyCode: 5, isSeparator: false, deviceClass: .builtIn),
            KeyEvent(timestamp: now.addingTimeInterval(10 * 60 + 1), keyCode: 44, isSeparator: true, deviceClass: .builtIn)
        ]

        let words: [WordIncrement] = [
            WordIncrement(timestamp: now.addingTimeInterval(-49 * 60), deviceClass: .builtIn),
            WordIncrement(timestamp: now.addingTimeInterval(10 * 60), deviceClass: .builtIn)
        ]

        let activeIncrements: [ActiveTypingIncrement] = [
            ActiveTypingIncrement(
                bucketStart: now.addingTimeInterval(-49 * 60),
                activeSeconds: 30,
                activeSecondsFlow: 30,
                activeSecondsSkill: 15
            )
        ]

        try await store.flush(events: events, wordIncrements: words, activeTypingIncrements: activeIncrements)

        let oneHour = try await store.snapshot(for: .h1, now: now)
        XCTAssertEqual(oneHour.totalKeystrokes, 2)
        XCTAssertEqual(oneHour.totalWords, 1)
        XCTAssertEqual(oneHour.wpmTrendSeries.filter { $0.words > 0 }.count, 1)
        XCTAssertEqual(oneHour.typingSpeedTrendSeries.filter { $0.flowWPM > 0 }.count, 1)
    }

    func testSnapshotIncludesWPMTrendAndTopAppsByWords() async throws {
        let dbURL = makeDatabaseURL(testName: #function)
        let store = try SQLiteStore(databaseURL: dbURL, retentionDays: 10_000)

        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let events: [KeyEvent] = [
            KeyEvent(
                timestamp: now.addingTimeInterval(-300),
                keyCode: 4,
                isSeparator: false,
                deviceClass: .builtIn,
                appBundleID: "com.apple.TextEdit",
                appName: "TextEdit"
            ),
            KeyEvent(
                timestamp: now.addingTimeInterval(-299),
                keyCode: 44,
                isSeparator: true,
                deviceClass: .builtIn,
                appBundleID: "com.apple.TextEdit",
                appName: "TextEdit"
            ),
            KeyEvent(
                timestamp: now.addingTimeInterval(-200),
                keyCode: 5,
                isSeparator: false,
                deviceClass: .builtIn,
                appBundleID: "com.apple.TextEdit",
                appName: "TextEdit"
            ),
            KeyEvent(
                timestamp: now.addingTimeInterval(-199),
                keyCode: 44,
                isSeparator: true,
                deviceClass: .builtIn,
                appBundleID: "com.apple.TextEdit",
                appName: "TextEdit"
            ),
            KeyEvent(
                timestamp: now.addingTimeInterval(-100),
                keyCode: 6,
                isSeparator: false,
                deviceClass: .builtIn,
                appBundleID: "com.apple.dt.Xcode",
                appName: "Xcode"
            ),
            KeyEvent(
                timestamp: now.addingTimeInterval(-99),
                keyCode: 44,
                isSeparator: true,
                deviceClass: .builtIn,
                appBundleID: "com.apple.dt.Xcode",
                appName: "Xcode"
            )
        ]

        let words: [WordIncrement] = [
            WordIncrement(
                timestamp: now.addingTimeInterval(-299),
                deviceClass: .builtIn,
                appBundleID: "com.apple.TextEdit",
                appName: "TextEdit"
            ),
            WordIncrement(
                timestamp: now.addingTimeInterval(-199),
                deviceClass: .builtIn,
                appBundleID: "com.apple.TextEdit",
                appName: "TextEdit"
            ),
            WordIncrement(
                timestamp: now.addingTimeInterval(-99),
                deviceClass: .builtIn,
                appBundleID: "com.apple.dt.Xcode",
                appName: "Xcode"
            )
        ]

        try await store.flush(events: events, wordIncrements: words, activeTypingIncrements: [])

        let snapshot = try await store.snapshot(for: .h1, now: now)

        XCTAssertEqual(snapshot.totalWords, 3)
        XCTAssertEqual(snapshot.topAppsByWords.count, 2)
        XCTAssertEqual(snapshot.topAppsByWords.first?.bundleID, "com.apple.TextEdit")
        XCTAssertEqual(snapshot.topAppsByWords.first?.wordCount, 2)
        XCTAssertEqual(snapshot.topAppsByWords.last?.bundleID, "com.apple.dt.Xcode")
        XCTAssertEqual(snapshot.topAppsByWords.last?.wordCount, 1)
        XCTAssertEqual(snapshot.wpmTrendSeries.reduce(0) { $0 + $1.words }, 3)
    }


    func testOneHourSnapshotUsesFiveMinuteBucketsForSpeedAndWords() async throws {
        let dbURL = makeDatabaseURL(testName: #function)
        let store = try SQLiteStore(databaseURL: dbURL, retentionDays: 10_000)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let wordTimes = [
            now.addingTimeInterval(-50 * 60),
            now.addingTimeInterval(-34 * 60),
            now.addingTimeInterval(-9 * 60)
        ]

        let events = wordTimes.flatMap { timestamp in
            [
                KeyEvent(timestamp: timestamp, keyCode: 4, isSeparator: false, deviceClass: .builtIn),
                KeyEvent(timestamp: timestamp.addingTimeInterval(1), keyCode: 44, isSeparator: true, deviceClass: .builtIn)
            ]
        }

        let words = wordTimes.map { timestamp in
            WordIncrement(timestamp: timestamp.addingTimeInterval(1), deviceClass: .builtIn)
        }

        let active: [ActiveTypingIncrement] = [
            ActiveTypingIncrement(bucketStart: wordTimes[0], activeSeconds: 30, activeSecondsFlow: 30, activeSecondsSkill: 10),
            ActiveTypingIncrement(bucketStart: wordTimes[1], activeSeconds: 15, activeSecondsFlow: 15, activeSecondsSkill: 8),
            ActiveTypingIncrement(bucketStart: wordTimes[2], activeSeconds: 60, activeSecondsFlow: 60, activeSecondsSkill: 12)
        ]

        try await store.flush(events: events, wordIncrements: words, activeTypingIncrements: active)

        let snapshot = try await store.snapshot(for: .h1, now: now)
        let nonZeroWordBuckets = snapshot.wpmTrendSeries.filter { $0.words > 0 }
        let nonZeroSpeedBuckets = snapshot.typingSpeedTrendSeries.filter { $0.flowWPM > 0 }
        let distinctFlowValues = Set(nonZeroSpeedBuckets.map { Int(($0.flowWPM * 10).rounded()) })

        XCTAssertEqual(snapshot.totalWords, 3)
        XCTAssertEqual(nonZeroWordBuckets.count, 3)
        XCTAssertEqual(nonZeroSpeedBuckets.count, 3)
        XCTAssertGreaterThan(distinctFlowValues.count, 1)
    }

    private func makeDatabaseURL(testName: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("typist-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory.appendingPathComponent("\(testName).sqlite3", isDirectory: false)
    }
}
