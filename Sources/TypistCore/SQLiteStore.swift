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
    case double(Double)
    case text(String)
    case null

    var intValue: Int {
        switch self {
        case let .int(value): return value
        case let .double(value): return Int(value)
        case .text, .null: return 0
        }
    }

    var doubleValue: Double {
        switch self {
        case let .double(value): return value
        case let .int(value): return Double(value)
        case .text, .null: return 0
        }
    }

    var textValue: String {
        switch self {
        case let .text(value): return value
        case .int, .double, .null: return ""
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

    public func flush(
        events: [KeyEvent],
        wordIncrements: [WordIncrement],
        activeTypingIncrements: [ActiveTypingIncrement],
        sessionData: [SessionFlushData] = []
    ) async throws {
        try queue.sync {
            try flushSync(events: events, wordIncrements: wordIncrements, activeTypingIncrements: activeTypingIncrements)
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
            try execute("DELETE FROM hourly_app_word_counts;")
            try execute("DELETE FROM daily_app_word_counts;")
            try execute("DELETE FROM hourly_typing_stats;")
            try execute("DELETE FROM daily_typing_stats;")
        }
    }

    private func flushSync(
        events: [KeyEvent],
        wordIncrements: [WordIncrement],
        activeTypingIncrements: [ActiveTypingIncrement]
    ) throws {
        guard !events.isEmpty || !wordIncrements.isEmpty || !activeTypingIncrements.isEmpty else { return }

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

            let upsertHourlyAppWord = try prepare(
                """
                INSERT INTO hourly_app_word_counts(bucket_start, app_bundle_id, app_name, count)
                VALUES(?, ?, ?, 1)
                ON CONFLICT(bucket_start, app_bundle_id)
                DO UPDATE SET count = count + 1, app_name = excluded.app_name;
                """
            )
            defer { sqlite3_finalize(upsertHourlyAppWord) }

            let upsertDailyAppWord = try prepare(
                """
                INSERT INTO daily_app_word_counts(bucket_start, app_bundle_id, app_name, count)
                VALUES(?, ?, ?, 1)
                ON CONFLICT(bucket_start, app_bundle_id)
                DO UPDATE SET count = count + 1, app_name = excluded.app_name;
                """
            )
            defer { sqlite3_finalize(upsertDailyAppWord) }

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
                let appIdentity = AppIdentity.normalize(bundleID: increment.appBundleID, appName: increment.appName)

                try run(upsertHourlyWord, bindings: [.int64(hourStart), .text(increment.deviceClass.rawValue)])
                try run(upsertDailyWord, bindings: [.int64(dayStart), .text(increment.deviceClass.rawValue)])
                try run(
                    upsertHourlyAppWord,
                    bindings: [.int64(hourStart), .text(appIdentity.bundleID), .text(appIdentity.appName)]
                )
                try run(
                    upsertDailyAppWord,
                    bindings: [.int64(dayStart), .text(appIdentity.bundleID), .text(appIdentity.appName)]
                )
            }

            // Store typing stats (active seconds and word counts for typing speed calculation)
            // First, aggregate word increments by hour bucket
            var wordCountByHour: [Int64: Int] = [:]
            for increment in wordIncrements {
                let hourStart = Int64(TimeBucket.startOfHour(for: increment.timestamp, calendar: calendar).timeIntervalSince1970)
                wordCountByHour[hourStart, default: 0] += 1
            }

            // Aggregate active typing by hour and day buckets (including flow/skill)
            var activeSecondsByHour: [Int64: Double] = [:]
            var activeSecondsByDay: [Int64: Double] = [:]
            var flowSecondsByHour: [Int64: Double] = [:]
            var flowSecondsByDay: [Int64: Double] = [:]
            var skillSecondsByHour: [Int64: Double] = [:]
            var skillSecondsByDay: [Int64: Double] = [:]
            for increment in activeTypingIncrements {
                let hourStart = Int64(increment.bucketStart.timeIntervalSince1970)
                let dayStart = Int64(TimeBucket.startOfDay(for: increment.bucketStart, calendar: calendar).timeIntervalSince1970)
                activeSecondsByHour[hourStart, default: 0] += increment.activeSeconds
                activeSecondsByDay[dayStart, default: 0] += increment.activeSeconds
                flowSecondsByHour[hourStart, default: 0] += increment.activeSecondsFlow
                flowSecondsByDay[dayStart, default: 0] += increment.activeSecondsFlow
                skillSecondsByHour[hourStart, default: 0] += increment.activeSecondsSkill
                skillSecondsByDay[dayStart, default: 0] += increment.activeSecondsSkill
            }

            // Upsert hourly typing stats
            for (hourStart, seconds) in activeSecondsByHour {
                let words = wordCountByHour[hourStart, default: 0]
                let flow = flowSecondsByHour[hourStart, default: 0]
                let skill = skillSecondsByHour[hourStart, default: 0]
                try execute(
                    """
                    INSERT INTO hourly_typing_stats(bucket_start, word_count, active_seconds, active_seconds_flow, active_seconds_skill)
                    VALUES(\(hourStart), \(words), \(seconds), \(flow), \(skill))
                    ON CONFLICT(bucket_start)
                    DO UPDATE SET word_count = word_count + \(words), active_seconds = active_seconds + \(seconds),
                    active_seconds_flow = active_seconds_flow + \(flow), active_seconds_skill = active_seconds_skill + \(skill);
                    """
                )
            }

            // Also update hourly stats for word counts without active seconds
            for (hourStart, words) in wordCountByHour where activeSecondsByHour[hourStart] == nil {
                try execute(
                    """
                    INSERT INTO hourly_typing_stats(bucket_start, word_count, active_seconds, active_seconds_flow, active_seconds_skill)
                    VALUES(\(hourStart), \(words), 0, 0, 0)
                    ON CONFLICT(bucket_start)
                    DO UPDATE SET word_count = word_count + \(words);
                    """
                )
            }

            // Aggregate word counts by day for daily stats
            var wordCountByDay: [Int64: Int] = [:]
            for increment in wordIncrements {
                let dayStart = Int64(TimeBucket.startOfDay(for: increment.timestamp, calendar: calendar).timeIntervalSince1970)
                wordCountByDay[dayStart, default: 0] += 1
            }

            // Upsert daily typing stats
            for (dayStart, seconds) in activeSecondsByDay {
                let words = wordCountByDay[dayStart, default: 0]
                let flow = flowSecondsByDay[dayStart, default: 0]
                let skill = skillSecondsByDay[dayStart, default: 0]
                try execute(
                    """
                    INSERT INTO daily_typing_stats(bucket_start, word_count, active_seconds, active_seconds_flow, active_seconds_skill)
                    VALUES(\(dayStart), \(words), \(seconds), \(flow), \(skill))
                    ON CONFLICT(bucket_start)
                    DO UPDATE SET word_count = word_count + \(words), active_seconds = active_seconds + \(seconds),
                    active_seconds_flow = active_seconds_flow + \(flow), active_seconds_skill = active_seconds_skill + \(skill);
                    """
                )
            }

            // Also update daily stats for word counts without active seconds
            for (dayStart, words) in wordCountByDay where activeSecondsByDay[dayStart] == nil {
                try execute(
                    """
                    INSERT INTO daily_typing_stats(bucket_start, word_count, active_seconds, active_seconds_flow, active_seconds_skill)
                    VALUES(\(dayStart), \(words), 0, 0, 0)
                    ON CONFLICT(bucket_start)
                    DO UPDATE SET word_count = word_count + \(words);
                    """
                )
            }

            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }

        try pruneIfNeeded(now: Date())
    }

    private func snapshotSync(for timeframe: Timeframe, now: Date) throws -> StatsSnapshot {
        if timeframe == .all {
            return try snapshotFromAggregateTablesForAll()
        }

        let granularity = timeframe.trendGranularity
        let keyRange = KeyboardKeyMapper.validKeyCodeRange
        let wordTable = granularity == .hour ? "hourly_word_counts" : "daily_word_counts"
        let appWordTable = granularity == .hour ? "hourly_app_word_counts" : "daily_app_word_counts"

        let startDate = timeframe.startDate(now: now, calendar: calendar)
        let startTimestamp = startDate.map { Int64($0.timeIntervalSince1970) }
        let startBucketTimestamp = startDate.map {
            Int64(TimeBucket.start(of: $0, granularity: granularity, calendar: calendar).timeIntervalSince1970)
        }

        let keyCodePredicate = "key_code >= \(keyRange.lowerBound) AND key_code <= \(keyRange.upperBound)"
        let eventFilterClause = startTimestamp == nil
            ? " WHERE \(keyCodePredicate)"
            : " WHERE ts >= ? AND \(keyCodePredicate)"
        let eventBindings = startTimestamp.map { [SQLiteBinding.int64($0)] } ?? []

        let aggregateFilterClause = startBucketTimestamp == nil ? "" : " WHERE bucket_start >= ?"
        let aggregateBindings = startBucketTimestamp.map { [SQLiteBinding.int64($0)] } ?? []

        let totalKeys = try querySingleInt(
            "SELECT COUNT(*) FROM event_ring_buffer\(eventFilterClause);",
            bindings: eventBindings
        )
        let totalWords = try wordCountFromEventRing(startTimestamp: startTimestamp, keyCodeRange: keyRange)

        let breakdownRows = try queryRows(
            "SELECT device_class, COUNT(*) FROM event_ring_buffer\(eventFilterClause) GROUP BY device_class;",
            bindings: eventBindings
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

        let keyDistributionRows = try queryRows(
            """
            SELECT key_code, COUNT(*) AS c
            FROM event_ring_buffer
            \(eventFilterClause)
            GROUP BY key_code
            ORDER BY c DESC, key_code ASC
            """,
            bindings: eventBindings
        )

        let keyDistribution = keyDistributionRows.compactMap { row -> TopKeyStat? in
            guard row.count >= 2 else { return nil }
            let keyCode = row[0].intValue
            let count = row[1].intValue
            guard count > 0 else { return nil }
            return TopKeyStat(keyCode: keyCode, keyName: KeyboardKeyMapper.displayName(for: keyCode), count: count)
        }
        let topKeys = Array(keyDistribution.prefix(8))

        let bucketSeconds = granularity == .hour ? 3600 : 86_400
        let trendRows = try queryRows(
            """
            SELECT (ts / \(bucketSeconds)) * \(bucketSeconds) AS bucket_start, COUNT(*)
            FROM event_ring_buffer
            \(eventFilterClause)
            GROUP BY bucket_start
            ORDER BY bucket_start ASC;
            """,
            bindings: eventBindings
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

        let wpmTrendSeries = fillWPMTrendIfNeeded(
            points: try queryWPMTrend(
                tableName: wordTable,
                filterClause: aggregateFilterClause,
                bindings: aggregateBindings,
                granularity: granularity
            ),
            timeframe: timeframe,
            granularity: granularity,
            now: now
        )

        let topAppsByWords = try queryTopAppsByWords(
            tableName: appWordTable,
            filterClause: aggregateFilterClause,
            bindings: aggregateBindings
        )

        let typingStatsTable = granularity == .hour ? "hourly_typing_stats" : "daily_typing_stats"
        let typingSpeedTrendSeries = fillTypingSpeedTrendIfNeeded(
            points: try queryTypingSpeedTrend(
                tableName: typingStatsTable,
                filterClause: aggregateFilterClause,
                bindings: aggregateBindings
            ),
            timeframe: timeframe,
            granularity: granularity,
            now: now
        )

        // Query aggregate session metrics
        let sessionMetrics = try querySessionAggregates(
            tableName: typingStatsTable,
            filterClause: aggregateFilterClause,
            bindings: aggregateBindings
        )

        return StatsSnapshot(
            timeframe: timeframe,
            totalKeystrokes: totalKeys,
            totalWords: totalWords,
            typedWords: sessionMetrics.typedWords,
            pastedWordsEst: sessionMetrics.pastedWordsEst,
            pasteEvents: sessionMetrics.pasteEvents,
            editEvents: sessionMetrics.editEvents,
            activeSecondsFlow: sessionMetrics.activeSecondsFlow,
            activeSecondsSkill: sessionMetrics.activeSecondsSkill,
            deviceBreakdown: DeviceBreakdown(builtIn: builtIn, external: external, unknown: unknown),
            keyDistribution: keyDistribution,
            topKeys: topKeys,
            trendSeries: trendSeries,
            wpmTrendSeries: wpmTrendSeries,
            typingSpeedTrendSeries: typingSpeedTrendSeries,
            topAppsByWords: topAppsByWords
        )
    }

    private struct SessionAggregates {
        var typedWords: Int = 0
        var pastedWordsEst: Int = 0
        var pasteEvents: Int = 0
        var editEvents: Int = 0
        var activeSecondsFlow: Double = 0
        var activeSecondsSkill: Double = 0
    }

    private func querySessionAggregates(
        tableName: String,
        filterClause: String,
        bindings: [SQLiteBinding]
    ) throws -> SessionAggregates {
        let rows = try queryRows(
            """
            SELECT COALESCE(SUM(active_seconds_flow), 0),
                   COALESCE(SUM(active_seconds_skill), 0),
                   COALESCE(SUM(typed_words), 0),
                   COALESCE(SUM(pasted_words_est), 0),
                   COALESCE(SUM(paste_events), 0),
                   COALESCE(SUM(edit_events), 0)
            FROM \(tableName)
            \(filterClause);
            """,
            bindings: bindings
        )

        guard let row = rows.first, row.count >= 6 else {
            return SessionAggregates()
        }

        return SessionAggregates(
            typedWords: row[2].intValue,
            pastedWordsEst: row[3].intValue,
            pasteEvents: row[4].intValue,
            editEvents: row[5].intValue,
            activeSecondsFlow: row[0].doubleValue,
            activeSecondsSkill: row[1].doubleValue
        )
    }

    private func snapshotFromAggregateTablesForAll() throws -> StatsSnapshot {
        let keyRange = KeyboardKeyMapper.validKeyCodeRange
        let keyCodePredicate = "key_code >= \(keyRange.lowerBound) AND key_code <= \(keyRange.upperBound)"

        let totalKeys = try querySingleInt(
            "SELECT COALESCE(SUM(count), 0) FROM daily_key_counts WHERE \(keyCodePredicate);",
            bindings: []
        )
        let totalWords = try querySingleInt(
            "SELECT COALESCE(SUM(count), 0) FROM daily_word_counts;",
            bindings: []
        )

        let breakdownRows = try queryRows(
            "SELECT device_class, COALESCE(SUM(count), 0) FROM daily_key_counts WHERE \(keyCodePredicate) GROUP BY device_class;",
            bindings: []
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

        let keyDistributionRows = try queryRows(
            """
            SELECT key_code, COALESCE(SUM(count), 0) AS c
            FROM daily_key_counts
            WHERE \(keyCodePredicate)
            GROUP BY key_code
            ORDER BY c DESC, key_code ASC
            """,
            bindings: []
        )

        let keyDistribution = keyDistributionRows.compactMap { row -> TopKeyStat? in
            guard row.count >= 2 else { return nil }
            let keyCode = row[0].intValue
            let count = row[1].intValue
            guard count > 0 else { return nil }
            return TopKeyStat(keyCode: keyCode, keyName: KeyboardKeyMapper.displayName(for: keyCode), count: count)
        }

        let trendRows = try queryRows(
            """
            SELECT bucket_start, COALESCE(SUM(count), 0)
            FROM daily_key_counts
            WHERE \(keyCodePredicate)
            GROUP BY bucket_start
            ORDER BY bucket_start ASC;
            """,
            bindings: []
        )

        let trendSeries = trendRows.compactMap { row -> TrendPoint? in
            guard row.count >= 2 else { return nil }
            let ts = row[0].intValue
            let count = row[1].intValue
            return TrendPoint(bucketStart: Date(timeIntervalSince1970: TimeInterval(ts)), count: count)
        }

        let wpmTrendSeries = try queryWPMTrend(
            tableName: "daily_word_counts",
            filterClause: "",
            bindings: [],
            granularity: .day
        )

        let topAppsByWords = try queryTopAppsByWords(
            tableName: "daily_app_word_counts",
            filterClause: "",
            bindings: []
        )

        let typingSpeedTrendSeries = try queryTypingSpeedTrend(
            tableName: "daily_typing_stats",
            filterClause: "",
            bindings: []
        )

        let sessionMetrics = try querySessionAggregates(
            tableName: "daily_typing_stats",
            filterClause: "",
            bindings: []
        )

        return StatsSnapshot(
            timeframe: .all,
            totalKeystrokes: totalKeys,
            totalWords: totalWords,
            typedWords: sessionMetrics.typedWords,
            pastedWordsEst: sessionMetrics.pastedWordsEst,
            pasteEvents: sessionMetrics.pasteEvents,
            editEvents: sessionMetrics.editEvents,
            activeSecondsFlow: sessionMetrics.activeSecondsFlow,
            activeSecondsSkill: sessionMetrics.activeSecondsSkill,
            deviceBreakdown: DeviceBreakdown(builtIn: builtIn, external: external, unknown: unknown),
            keyDistribution: keyDistribution,
            topKeys: Array(keyDistribution.prefix(8)),
            trendSeries: trendSeries,
            wpmTrendSeries: wpmTrendSeries,
            typingSpeedTrendSeries: typingSpeedTrendSeries,
            topAppsByWords: topAppsByWords
        )
    }

    private func wordCountFromEventRing(startTimestamp: Int64?, keyCodeRange: ClosedRange<Int>) throws -> Int {
        var inWord = false
        if let startTimestamp {
            let priorRows = try queryRows(
                """
                SELECT key_code
                FROM event_ring_buffer
                WHERE ts < ? AND key_code >= \(keyCodeRange.lowerBound) AND key_code <= \(keyCodeRange.upperBound)
                ORDER BY ts DESC, rowid DESC
                LIMIT 1;
                """,
                bindings: [.int64(startTimestamp)]
            )

            if let priorKeyCode = priorRows.first?.first?.intValue {
                inWord = !KeyboardKeyMapper.isSeparator(priorKeyCode)
            }
        }

        let eventRows: [[SQLiteValue]]
        if let startTimestamp {
            eventRows = try queryRows(
                """
                SELECT key_code
                FROM event_ring_buffer
                WHERE ts >= ? AND key_code >= \(keyCodeRange.lowerBound) AND key_code <= \(keyCodeRange.upperBound)
                ORDER BY ts ASC, rowid ASC;
                """,
                bindings: [.int64(startTimestamp)]
            )
        } else {
            eventRows = try queryRows(
                """
                SELECT key_code
                FROM event_ring_buffer
                WHERE key_code >= \(keyCodeRange.lowerBound) AND key_code <= \(keyCodeRange.upperBound)
                ORDER BY ts ASC, rowid ASC;
                """,
                bindings: []
            )
        }

        var words = 0
        for row in eventRows where !row.isEmpty {
            let keyCode = row[0].intValue
            if KeyboardKeyMapper.isSeparator(keyCode) {
                if inWord {
                    words += 1
                    inWord = false
                }
            } else {
                inWord = true
            }
        }

        return words
    }

    private func queryWPMTrend(
        tableName: String,
        filterClause: String,
        bindings: [SQLiteBinding],
        granularity: TimeBucketGranularity
    ) throws -> [WPMTrendPoint] {
        let rows = try queryRows(
            """
            SELECT bucket_start, COALESCE(SUM(count), 0) AS c
            FROM \(tableName)
            \(filterClause)
            GROUP BY bucket_start
            ORDER BY bucket_start ASC;
            """,
            bindings: bindings
        )

        return rows.compactMap { row -> WPMTrendPoint? in
            guard row.count >= 2 else { return nil }
            let bucketStart = Date(timeIntervalSince1970: TimeInterval(row[0].intValue))
            let words = row[1].intValue
            return WPMTrendPoint(
                bucketStart: bucketStart,
                words: words,
                rate: Double(words) / granularity.bucketMinutes
            )
        }
    }

    private func queryTopAppsByWords(
        tableName: String,
        filterClause: String,
        bindings: [SQLiteBinding]
    ) throws -> [AppWordStat] {
        let rows = try queryRows(
            """
            SELECT app_bundle_id, COALESCE(MAX(app_name), app_bundle_id), COALESCE(SUM(count), 0) AS c
            FROM \(tableName)
            \(filterClause)
            GROUP BY app_bundle_id
            ORDER BY c DESC, app_bundle_id ASC
            LIMIT 20;
            """,
            bindings: bindings
        )

        return rows.compactMap { row -> AppWordStat? in
            guard row.count >= 3 else { return nil }
            let bundleID = row[0].textValue
            let appName = row[1].textValue
            let wordCount = row[2].intValue
            guard wordCount > 0 else { return nil }
            return AppWordStat(bundleID: bundleID, appName: appName, wordCount: wordCount)
        }
    }

    private func queryTypingSpeedTrend(
        tableName: String,
        filterClause: String,
        bindings: [SQLiteBinding]
    ) throws -> [TypingSpeedTrendPoint] {
        let rows = try queryRows(
            """
            SELECT bucket_start, word_count, active_seconds, active_seconds_flow, active_seconds_skill
            FROM \(tableName)
            \(filterClause)
            ORDER BY bucket_start ASC;
            """,
            bindings: bindings
        )

        return rows.compactMap { row -> TypingSpeedTrendPoint? in
            guard row.count >= 3 else { return nil }
            let bucketStart = Date(timeIntervalSince1970: TimeInterval(row[0].intValue))
            let words = row[1].intValue
            let activeSeconds = row[2].doubleValue
            let flowSeconds = row.count >= 4 ? row[3].doubleValue : activeSeconds
            let skillSeconds = row.count >= 5 ? row[4].doubleValue : activeSeconds
            return TypingSpeedTrendPoint(
                bucketStart: bucketStart,
                words: words,
                activeSeconds: activeSeconds,
                activeSecondsFlow: flowSeconds,
                activeSecondsSkill: skillSeconds
            )
        }
    }

    private func fillTypingSpeedTrendIfNeeded(
        points: [TypingSpeedTrendPoint],
        timeframe: Timeframe,
        granularity: TimeBucketGranularity,
        now: Date
    ) -> [TypingSpeedTrendPoint] {
        guard timeframe != .all else {
            return points
        }

        guard let startDate = timeframe.startDate(now: now, calendar: calendar) else {
            return points
        }

        let startBucket = TimeBucket.start(of: startDate, granularity: granularity, calendar: calendar)
        let endBucket = TimeBucket.start(of: now, granularity: granularity, calendar: calendar)

        var wordsMap: [Date: Int] = [:]
        var secondsMap: [Date: Double] = [:]
        var flowMap: [Date: Double] = [:]
        var skillMap: [Date: Double] = [:]
        for point in points {
            wordsMap[point.bucketStart] = point.words
            secondsMap[point.bucketStart] = point.activeSeconds
            flowMap[point.bucketStart] = point.activeSecondsFlow
            skillMap[point.bucketStart] = point.activeSecondsSkill
        }

        var series: [TypingSpeedTrendPoint] = []
        var cursor = startBucket
        while cursor <= endBucket {
            series.append(
                TypingSpeedTrendPoint(
                    bucketStart: cursor,
                    words: wordsMap[cursor, default: 0],
                    activeSeconds: secondsMap[cursor, default: 0],
                    activeSecondsFlow: flowMap[cursor, default: 0],
                    activeSecondsSkill: skillMap[cursor, default: 0]
                )
            )
            cursor = TimeBucket.advance(cursor, by: granularity, calendar: calendar)
        }

        return series
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
            CREATE TABLE IF NOT EXISTS hourly_app_word_counts (
                bucket_start INTEGER NOT NULL,
                app_bundle_id TEXT NOT NULL,
                app_name TEXT NOT NULL,
                count INTEGER NOT NULL,
                PRIMARY KEY(bucket_start, app_bundle_id)
            );
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS daily_app_word_counts (
                bucket_start INTEGER NOT NULL,
                app_bundle_id TEXT NOT NULL,
                app_name TEXT NOT NULL,
                count INTEGER NOT NULL,
                PRIMARY KEY(bucket_start, app_bundle_id)
            );
            """
        )

        // Typing speed tracking: stores active typing seconds and word count per bucket
        try execute(
            """
            CREATE TABLE IF NOT EXISTS hourly_typing_stats (
                bucket_start INTEGER NOT NULL PRIMARY KEY,
                word_count INTEGER NOT NULL DEFAULT 0,
                active_seconds REAL NOT NULL DEFAULT 0,
                active_seconds_flow REAL NOT NULL DEFAULT 0,
                active_seconds_skill REAL NOT NULL DEFAULT 0,
                typed_words INTEGER NOT NULL DEFAULT 0,
                pasted_words_est INTEGER NOT NULL DEFAULT 0,
                paste_events INTEGER NOT NULL DEFAULT 0,
                edit_events INTEGER NOT NULL DEFAULT 0
            );
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS daily_typing_stats (
                bucket_start INTEGER NOT NULL PRIMARY KEY,
                word_count INTEGER NOT NULL DEFAULT 0,
                active_seconds REAL NOT NULL DEFAULT 0,
                active_seconds_flow REAL NOT NULL DEFAULT 0,
                active_seconds_skill REAL NOT NULL DEFAULT 0,
                typed_words INTEGER NOT NULL DEFAULT 0,
                pasted_words_est INTEGER NOT NULL DEFAULT 0,
                paste_events INTEGER NOT NULL DEFAULT 0,
                edit_events INTEGER NOT NULL DEFAULT 0
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

        // Migrate existing databases: add new columns if missing
        try migrateTypingStatsColumns()
    }

    private func migrateTypingStatsColumns() throws {
        let newColumns = [
            "active_seconds_flow REAL NOT NULL DEFAULT 0",
            "active_seconds_skill REAL NOT NULL DEFAULT 0",
            "typed_words INTEGER NOT NULL DEFAULT 0",
            "pasted_words_est INTEGER NOT NULL DEFAULT 0",
            "paste_events INTEGER NOT NULL DEFAULT 0",
            "edit_events INTEGER NOT NULL DEFAULT 0"
        ]

        for table in ["hourly_typing_stats", "daily_typing_stats"] {
            for columnDef in newColumns {
                // ALTER TABLE ADD COLUMN is a no-op if column exists (SQLite returns error we ignore)
                try? execute("ALTER TABLE \(table) ADD COLUMN \(columnDef);")
            }
        }
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

        // Prune raw events
        let statement = try prepare("DELETE FROM event_ring_buffer WHERE ts < ?;")
        defer { sqlite3_finalize(statement) }
        try run(statement, bindings: [.int64(cutoffTs)])

        // Prune hourly aggregate tables (keep daily tables for long-term history)
        try execute("DELETE FROM hourly_key_counts WHERE bucket_start < \(cutoffTs);")
        try execute("DELETE FROM hourly_word_counts WHERE bucket_start < \(cutoffTs);")
        try execute("DELETE FROM hourly_app_word_counts WHERE bucket_start < \(cutoffTs);")
        try execute("DELETE FROM hourly_typing_stats WHERE bucket_start < \(cutoffTs);")

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

    private func fillWPMTrendIfNeeded(
        points: [WPMTrendPoint],
        timeframe: Timeframe,
        granularity: TimeBucketGranularity,
        now: Date
    ) -> [WPMTrendPoint] {
        guard timeframe != .all else {
            return points
        }

        guard let startDate = timeframe.startDate(now: now, calendar: calendar) else {
            return points
        }

        let startBucket = TimeBucket.start(of: startDate, granularity: granularity, calendar: calendar)
        let endBucket = TimeBucket.start(of: now, granularity: granularity, calendar: calendar)

        let pointMap = Dictionary(uniqueKeysWithValues: points.map { ($0.bucketStart, $0.words) })
        var series: [WPMTrendPoint] = []

        var cursor = startBucket
        while cursor <= endBucket {
            let words = pointMap[cursor, default: 0]
            series.append(
                WPMTrendPoint(
                    bucketStart: cursor,
                    words: words,
                    rate: Double(words) / granularity.bucketMinutes
                )
            )
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
                case SQLITE_FLOAT:
                    row.append(.double(sqlite3_column_double(statement, Int32(column))))
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
