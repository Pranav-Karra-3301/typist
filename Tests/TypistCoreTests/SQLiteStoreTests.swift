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

        try await store.flush(events: events, wordIncrements: words)
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

        try await store.flush(events: events, wordIncrements: [])

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

        try await store.flush(events: events, wordIncrements: [])

        let oneHour = try await store.snapshot(for: .h1, now: now)
        XCTAssertEqual(oneHour.totalWords, 1)
    }

    private func makeDatabaseURL(testName: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("typist-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory.appendingPathComponent("\(testName).sqlite3", isDirectory: false)
    }
}
