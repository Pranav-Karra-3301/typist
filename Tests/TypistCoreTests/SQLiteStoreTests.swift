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

    private func makeDatabaseURL(testName: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("typist-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory.appendingPathComponent("\(testName).sqlite3", isDirectory: false)
    }
}
