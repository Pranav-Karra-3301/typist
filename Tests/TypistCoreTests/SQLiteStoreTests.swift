import Foundation
import XCTest
@testable import TypistCore

final class SQLiteStoreTests: XCTestCase {
    func testSnapshotReturnsCountsForKeysAndWords() async throws {
        let dbURL = makeDatabaseURL(testName: #function)
        let store = try SQLiteStore(databaseURL: dbURL)

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

    private func makeDatabaseURL(testName: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("typist-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory.appendingPathComponent("\(testName).sqlite3", isDirectory: false)
    }
}
