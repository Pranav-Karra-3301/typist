import Foundation
import SQLite3

public enum SQLiteStoreError: Error, CustomStringConvertible, LocalizedError {
    case openFailed(path: String)
    case prepareFailed(message: String)
    case executeFailed(message: String)
    case bindFailed(message: String)
    case stepFailed(message: String)

    public var description: String {
        switch self {
        case let .openFailed(path):
            return "Failed to open SQLite database at \(path)."
        case let .prepareFailed(message):
            return "Failed to prepare SQLite statement: \(message)"
        case let .executeFailed(message):
            return "Failed to execute SQLite statement: \(message)"
        case let .bindFailed(message):
            return "Failed to bind SQLite statement: \(message)"
        case let .stepFailed(message):
            return "Failed to step SQLite statement: \(message)"
        }
    }

    public var errorDescription: String? {
        description
    }
}

private enum SQLiteBinding {
    case int64(Int64)
    case text(String)
}

private enum SQLiteValue {
    case int(Int)
    case text(String)
    case null

    var intValue: Int {
        switch self {
        case let .int(value): return value
        case .text, .null: return 0
        }
    }

    var textValue: String {
        switch self {
        case let .text(value): return value
        case .int, .null: return ""
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class SQLiteStore: TypistStore, @unchecked Sendable {
    private let queue = DispatchQueue(label: "typist.sqlite.store", qos: .utility)

    private var db: OpaquePointer?
    private let retentionDays: Int
    private let calendar: Calendar
    private var lastPruneDate: Date?

    public init(databaseURL: URL, retentionDays: Int = 90, calendar: Calendar = .current) throws {
        self.retentionDays = retentionDays
        self.calendar = calendar

        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(databaseURL.path, &db, flags, nil) != SQLITE_OK {
            throw SQLiteStoreError.openFailed(path: databaseURL.path)
        }

        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
        try createSchema()
        try sanitizeInvalidKeyCodes()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    public func flush(events: [KeyEvent], wordIncrements: [WordIncrement]) async throws {
        try queue.sync {
            try flushSync(events: events, wordIncrements: wordIncrements)
        }
    }

    public func snapshot(for timeframe: Timeframe, now: Date = Date()) async throws -> StatsSnapshot {
        try queue.sync {
            try snapshotSync(for: timeframe, now: now)
        }
    }

    public func resetAllData() async throws {
        try queue.sync {
            try execute("DELETE FROM event_ring_buffer;")
            try execute("DELETE FROM hourly_key_counts;")
            try execute("DELETE FROM daily_key_counts;")
            try execute("DELETE FROM hourly_word_counts;")
            try execute("DELETE FROM daily_word_counts;")
        }
    }

    private func flushSync(events: [KeyEvent], wordIncrements: [WordIncrement]) throws {
        guard !events.isEmpty || !wordIncrements.isEmpty else { return }

        try execute("BEGIN IMMEDIATE TRANSACTION;")

        do {
            let insertEvent = try prepare(
                "INSERT INTO event_ring_buffer(ts, key_code, device_class) VALUES(?, ?, ?);"
            )
            defer { sqlite3_finalize(insertEvent) }

            let upsertHourlyKey = try prepare(
                """
                INSERT INTO hourly_key_counts(bucket_start, key_code, device_class, count)
                VALUES(?, ?, ?, 1)
                ON CONFLICT(bucket_start, key_code, device_class)
                DO UPDATE SET count = count + 1;
                """
            )
            defer { sqlite3_finalize(upsertHourlyKey) }

            let upsertDailyKey = try prepare(
                """
                INSERT INTO daily_key_counts(bucket_start, key_code, device_class, count)
                VALUES(?, ?, ?, 1)
                ON CONFLICT(bucket_start, key_code, device_class)
                DO UPDATE SET count = count + 1;
                """
            )
            defer { sqlite3_finalize(upsertDailyKey) }

            let upsertHourlyWord = try prepare(
                """
                INSERT INTO hourly_word_counts(bucket_start, device_class, count)
                VALUES(?, ?, 1)
                ON CONFLICT(bucket_start, device_class)
                DO UPDATE SET count = count + 1;
                """
            )
            defer { sqlite3_finalize(upsertHourlyWord) }

            let upsertDailyWord = try prepare(
                """
                INSERT INTO daily_word_counts(bucket_start, device_class, count)
                VALUES(?, ?, 1)
                ON CONFLICT(bucket_start, device_class)
                DO UPDATE SET count = count + 1;
                """
            )
            defer { sqlite3_finalize(upsertDailyWord) }

            for event in events where KeyboardKeyMapper.isTrackableKeyCode(event.keyCode) {
                let ts = Int64(event.timestamp.timeIntervalSince1970)
                let hourStart = Int64(TimeBucket.startOfHour(for: event.timestamp, calendar: calendar).timeIntervalSince1970)
                let dayStart = Int64(TimeBucket.startOfDay(for: event.timestamp, calendar: calendar).timeIntervalSince1970)

                try run(
                    insertEvent,
                    bindings: [.int64(ts), .int64(Int64(event.keyCode)), .text(event.deviceClass.rawValue)]
                )

                try run(
                    upsertHourlyKey,
                    bindings: [.int64(hourStart), .int64(Int64(event.keyCode)), .text(event.deviceClass.rawValue)]
                )

                try run(
                    upsertDailyKey,
                    bindings: [.int64(dayStart), .int64(Int64(event.keyCode)), .text(event.deviceClass.rawValue)]
                )
            }

            for increment in wordIncrements {
                let hourStart = Int64(TimeBucket.startOfHour(for: increment.timestamp, calendar: calendar).timeIntervalSince1970)
                let dayStart = Int64(TimeBucket.startOfDay(for: increment.timestamp, calendar: calendar).timeIntervalSince1970)

                try run(upsertHourlyWord, bindings: [.int64(hourStart), .text(increment.deviceClass.rawValue)])
                try run(upsertDailyWord, bindings: [.int64(dayStart), .text(increment.deviceClass.rawValue)])
            }

            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }

        try pruneIfNeeded(now: Date())
    }

    private func snapshotSync(for timeframe: Timeframe, now: Date) throws -> StatsSnapshot {
        let granularity = timeframe == .all ? TimeBucketGranularity.day : timeframe.trendGranularity
        let keyTable = granularity == .hour ? "hourly_key_counts" : "daily_key_counts"
        let wordTable = granularity == .hour ? "hourly_word_counts" : "daily_word_counts"
        let keyRange = KeyboardKeyMapper.validKeyCodeRange

        let startDate = timeframe.startDate(now: now, calendar: calendar)
        let startTimestamp: Int64?
        if let startDate {
            startTimestamp = Int64(TimeBucket.start(of: startDate, granularity: granularity, calendar: calendar).timeIntervalSince1970)
        } else {
            startTimestamp = nil
        }

        let keyCodePredicate = "key_code >= \(keyRange.lowerBound) AND key_code <= \(keyRange.upperBound)"
        let keyFilterClause = startTimestamp == nil
            ? " WHERE \(keyCodePredicate)"
            : " WHERE bucket_start >= ? AND \(keyCodePredicate)"
        let wordFilterClause = startTimestamp == nil ? "" : " WHERE bucket_start >= ?"
        let bindings = startTimestamp.map { [SQLiteBinding.int64($0)] } ?? []

        let totalKeys = try querySingleInt(
            "SELECT COALESCE(SUM(count), 0) FROM \(keyTable)\(keyFilterClause);",
            bindings: bindings
        )

        let totalWords = try querySingleInt(
            "SELECT COALESCE(SUM(count), 0) FROM \(wordTable)\(wordFilterClause);",
            bindings: bindings
        )

        let breakdownRows = try queryRows(
            "SELECT device_class, COALESCE(SUM(count), 0) FROM \(keyTable)\(keyFilterClause) GROUP BY device_class;",
            bindings: bindings
        )

        var builtIn = 0
        var external = 0
        var unknown = 0

        for row in breakdownRows where row.count >= 2 {
            let device = row[0].textValue
            let count = row[1].intValue

            switch device {
            case DeviceClass.builtIn.rawValue: builtIn = count
            case DeviceClass.external.rawValue: external = count
            default: unknown = count
            }
        }

        let topKeyRows = try queryRows(
            """
            SELECT key_code, COALESCE(SUM(count), 0) AS c
            FROM \(keyTable)
            \(keyFilterClause)
            GROUP BY key_code
            ORDER BY c DESC
            LIMIT 8;
            """,
            bindings: bindings
        )

        let topKeys = topKeyRows.compactMap { row -> TopKeyStat? in
            guard row.count >= 2 else { return nil }
            let keyCode = row[0].intValue
            let count = row[1].intValue
            return TopKeyStat(keyCode: keyCode, keyName: KeyboardKeyMapper.displayName(for: keyCode), count: count)
        }

        let trendRows = try queryRows(
            """
            SELECT bucket_start, COALESCE(SUM(count), 0)
            FROM \(keyTable)
            \(keyFilterClause)
            GROUP BY bucket_start
            ORDER BY bucket_start ASC;
            """,
            bindings: bindings
        )

        let rawTrend = trendRows.compactMap { row -> TrendPoint? in
            guard row.count >= 2 else { return nil }
            let ts = row[0].intValue
            let count = row[1].intValue
            return TrendPoint(bucketStart: Date(timeIntervalSince1970: TimeInterval(ts)), count: count)
        }

        let trendSeries = fillTrendIfNeeded(
            points: rawTrend,
            timeframe: timeframe,
            granularity: granularity,
            now: now
        )

        return StatsSnapshot(
            timeframe: timeframe,
            totalKeystrokes: totalKeys,
            totalWords: totalWords,
            deviceBreakdown: DeviceBreakdown(builtIn: builtIn, external: external, unknown: unknown),
            topKeys: topKeys,
            trendSeries: trendSeries
        )
    }

    private func createSchema() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS hourly_key_counts (
                bucket_start INTEGER NOT NULL,
                key_code INTEGER NOT NULL,
                device_class TEXT NOT NULL,
                count INTEGER NOT NULL,
                PRIMARY KEY(bucket_start, key_code, device_class)
            );
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS daily_key_counts (
                bucket_start INTEGER NOT NULL,
                key_code INTEGER NOT NULL,
                device_class TEXT NOT NULL,
                count INTEGER NOT NULL,
                PRIMARY KEY(bucket_start, key_code, device_class)
            );
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS hourly_word_counts (
                bucket_start INTEGER NOT NULL,
                device_class TEXT NOT NULL,
                count INTEGER NOT NULL,
                PRIMARY KEY(bucket_start, device_class)
            );
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS daily_word_counts (
                bucket_start INTEGER NOT NULL,
                device_class TEXT NOT NULL,
                count INTEGER NOT NULL,
                PRIMARY KEY(bucket_start, device_class)
            );
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS event_ring_buffer (
                ts INTEGER NOT NULL,
                key_code INTEGER NOT NULL,
                device_class TEXT NOT NULL
            );
            """
        )

        try execute("CREATE INDEX IF NOT EXISTS idx_event_ring_buffer_ts ON event_ring_buffer(ts);")
    }

    private func sanitizeInvalidKeyCodes() throws {
        let range = KeyboardKeyMapper.validKeyCodeRange
        try execute("DELETE FROM event_ring_buffer WHERE key_code < \(range.lowerBound) OR key_code > \(range.upperBound);")
        try execute("DELETE FROM hourly_key_counts WHERE key_code < \(range.lowerBound) OR key_code > \(range.upperBound);")
        try execute("DELETE FROM daily_key_counts WHERE key_code < \(range.lowerBound) OR key_code > \(range.upperBound);")
    }

    private func pruneIfNeeded(now: Date) throws {
        if let lastPruneDate, now.timeIntervalSince(lastPruneDate) < 3600 {
            return
        }

        let cutoff = now.addingTimeInterval(TimeInterval(-retentionDays * 86_400))
        let cutoffTs = Int64(cutoff.timeIntervalSince1970)

        let statement = try prepare("DELETE FROM event_ring_buffer WHERE ts < ?;")
        defer { sqlite3_finalize(statement) }

        try run(statement, bindings: [.int64(cutoffTs)])
        lastPruneDate = now
    }

    private func fillTrendIfNeeded(
        points: [TrendPoint],
        timeframe: Timeframe,
        granularity: TimeBucketGranularity,
        now: Date
    ) -> [TrendPoint] {
        guard timeframe != .all else {
            return points
        }

        guard let startDate = timeframe.startDate(now: now, calendar: calendar) else {
            return points
        }

        let startBucket = TimeBucket.start(of: startDate, granularity: granularity, calendar: calendar)
        let endBucket = TimeBucket.start(of: now, granularity: granularity, calendar: calendar)

        let pointMap = Dictionary(uniqueKeysWithValues: points.map { ($0.bucketStart, $0.count) })
        var series: [TrendPoint] = []

        var cursor = startBucket
        while cursor <= endBucket {
            series.append(TrendPoint(bucketStart: cursor, count: pointMap[cursor, default: 0]))
            cursor = TimeBucket.advance(cursor, by: granularity, calendar: calendar)
        }

        return series
    }

    private func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorPointer)

        guard result == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_free(errorPointer)
            throw SQLiteStoreError.executeFailed(message: message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(message: lastErrorMessage())
        }
        return statement
    }

    private func run(_ statement: OpaquePointer?, bindings: [SQLiteBinding]) throws {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)

        try bind(statement, bindings: bindings)

        let stepStatus = sqlite3_step(statement)
        guard stepStatus == SQLITE_DONE || stepStatus == SQLITE_ROW else {
            throw SQLiteStoreError.stepFailed(message: lastErrorMessage())
        }
    }

    private func querySingleInt(_ sql: String, bindings: [SQLiteBinding]) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(statement, bindings: bindings)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    private func queryRows(_ sql: String, bindings: [SQLiteBinding]) throws -> [[SQLiteValue]] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(statement, bindings: bindings)

        var rows: [[SQLiteValue]] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let columnCount = Int(sqlite3_column_count(statement))
            var row: [SQLiteValue] = []
            row.reserveCapacity(columnCount)

            for column in 0..<columnCount {
                let type = sqlite3_column_type(statement, Int32(column))
                switch type {
                case SQLITE_INTEGER:
                    row.append(.int(Int(sqlite3_column_int64(statement, Int32(column)))))
                case SQLITE_TEXT:
                    if let cString = sqlite3_column_text(statement, Int32(column)) {
                        row.append(.text(String(cString: cString)))
                    } else {
                        row.append(.text(""))
                    }
                default:
                    row.append(.null)
                }
            }

            rows.append(row)
        }

        return rows
    }

    private func bind(_ statement: OpaquePointer?, bindings: [SQLiteBinding]) throws {
        for (index, binding) in bindings.enumerated() {
            let parameterIndex = Int32(index + 1)
            let status: Int32

            switch binding {
            case let .int64(value):
                status = sqlite3_bind_int64(statement, parameterIndex, value)
            case let .text(value):
                status = value.withCString { pointer in
                    sqlite3_bind_text(statement, parameterIndex, pointer, -1, sqliteTransient)
                }
            }

            guard status == SQLITE_OK else {
                throw SQLiteStoreError.bindFailed(message: lastErrorMessage())
            }
        }
    }

    private func lastErrorMessage() -> String {
        guard let db else { return "No SQLite database handle" }
        return String(cString: sqlite3_errmsg(db))
    }
}
