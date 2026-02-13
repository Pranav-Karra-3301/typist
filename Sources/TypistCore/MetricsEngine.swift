import Foundation

public actor MetricsEngine {
    private let store: PersistenceWriting
    private let queryService: StatsQuerying
    private let config: SessionConfig

    // Per-app session tracking
    private var sessions: [String: TypingSession] = [:] // keyed by appBundleID
    private var wordCounters: [String: WordCounterStateMachine] = [:] // keyed by appBundleID

    // Pending data for flush
    private var pendingEvents: [KeyEvent] = []
    private var pendingWordIncrements: [WordIncrement] = []
    private var pendingActiveTypingByBucket: [Date: Double] = [:]
    private var pendingActiveFlowByBucket: [Date: Double] = [:]
    private var pendingActiveSkillByBucket: [Date: Double] = [:]
    // Per-bucket session metrics
    private var pendingTypedWordsByBucket: [Date: Int] = [:]
    private var pendingPastedWordsByBucket: [Date: Int] = [:]
    private var pendingPasteEventsByBucket: [Date: Int] = [:]
    private var pendingEditEventsByBucket: [Date: Int] = [:]
    // Last text-producing event time per app (monotonic)
    private var lastTextEventMonotonic: [String: TimeInterval] = [:]
    private var lastTextEventWallClock: [String: Date] = [:]

    // Legacy: still track last keystroke time for backwards compat active typing bucket
    private var lastKeystrokeTime: Date?

    private let flushInterval: Duration
    private let flushThreshold: Int

    private var flushLoopTask: Task<Void, Never>?
    private var isStarted = false
    private var totalIngestedEvents = 0
    private var totalFlushes = 0
    private var totalFlushedEvents = 0
    private var lastIngestAt: Date?
    private var lastFlushAt: Date?
    private var lastFlushError: String?
    private let ignoredWordCountBundleSuffixes: Set<String> = [
        "wispr",
        "superwispr",
        "superwhisper",
        "wisprflow",
        "dictation",
        "kotoeri",
        "speech",
        "speechrecognition",
        "com.apple.speech",
        "voiceinput",
        "dictation",
        "dictate",
        "dictationim",
        "whisperspeech",
        "com.apple.dictation"
    ]
    private let ignoredWordCountAppNameFragments: Set<String> = [
        "wispr",
        "super whisper",
        "superwispr",
        "wispr flow",
        "wisprflow",
        "dictation",
        "voice dictation",
        "speech to text",
        "voice input",
        "speech recognition",
        "kotoeri",
        "voice typing",
        "dictate",
        "whisper flow",
        "dictationim",
        "super whisper dictation"
    ]

    public init(
        store: PersistenceWriting,
        queryService: StatsQuerying,
        flushInterval: Duration = .seconds(5),
        flushThreshold: Int = 200,
        sessionConfig: SessionConfig = .default
    ) {
        self.store = store
        self.queryService = queryService
        self.flushInterval = flushInterval
        self.flushThreshold = flushThreshold
        self.config = sessionConfig
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        flushLoopTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: flushInterval)
                do {
                    try await flushIfNeeded(force: true)
                } catch {
                    lastFlushError = error.localizedDescription
                }
            }
        }
    }

    public func stop() async {
        flushLoopTask?.cancel()
        flushLoopTask = nil

        // Flush last words from all active sessions
        endAllSessions()

        do {
            try await flushIfNeeded(force: true)
        } catch {
            lastFlushError = error.localizedDescription
        }
        isStarted = false
    }

    public func resetInMemoryState() {
        pendingEvents.removeAll(keepingCapacity: false)
        pendingWordIncrements.removeAll(keepingCapacity: false)
        pendingActiveTypingByBucket.removeAll(keepingCapacity: false)
        pendingActiveFlowByBucket.removeAll(keepingCapacity: false)
        pendingActiveSkillByBucket.removeAll(keepingCapacity: false)
        pendingTypedWordsByBucket.removeAll(keepingCapacity: false)
        pendingPastedWordsByBucket.removeAll(keepingCapacity: false)
        pendingPasteEventsByBucket.removeAll(keepingCapacity: false)
        pendingEditEventsByBucket.removeAll(keepingCapacity: false)
        sessions.removeAll()
        wordCounters.removeAll()
        lastTextEventMonotonic.removeAll()
        lastTextEventWallClock.removeAll()
        lastKeystrokeTime = nil
    }

    public func diagnostics() -> MetricsEngineDiagnostics {
        MetricsEngineDiagnostics(
            isStarted: isStarted,
            pendingEvents: pendingEvents.count,
            pendingWordIncrements: pendingWordIncrements.count,
            totalIngestedEvents: totalIngestedEvents,
            totalFlushes: totalFlushes,
            totalFlushedEvents: totalFlushedEvents,
            lastIngestAt: lastIngestAt,
            lastFlushAt: lastFlushAt,
            lastFlushError: lastFlushError
        )
    }

    public func ingest(_ event: KeyEvent) async {
        let appID = event.appBundleID ?? AppIdentity.unknownBundleID
        let shouldCountForWordStats = shouldCountEventInWordStats(event)
        let eventForStorage = event.withWordCounting(shouldCountForWordStats)
        pendingEvents.append(eventForStorage)
        totalIngestedEvents += 1
        lastIngestAt = event.timestamp

        let appName = event.appName ?? AppIdentity.unknownAppName
        let isDelete = KeyboardKeyMapper.isDeleteKey(event.keyCode)
        let isPaste = event.isPasteChord

        if !shouldCountForWordStats {
            clearWordCountState(for: appID, event: event)

            if pendingEvents.count >= flushThreshold {
                do {
                    try await flushIfNeeded(force: true)
                } catch {
                    lastFlushError = error.localizedDescription
                }
            }
            return
        }

        // Check for session timeout or app switch
        if let existingSession = sessions[appID] {
            let monotonicDelta = event.monotonicTime - existingSession.lastMonotonicTime
            if monotonicDelta > config.sessionTimeout {
                // End the old session (flush last word)
                endSession(forApp: appID)
                // Start new session
                startSession(appID: appID, appName: appName, event: event)
            }
        } else {
            // No existing session for this app
            startSession(appID: appID, appName: appName, event: event)
        }

        // --- Process text-producing events for timing ---
        if event.isTextProducing {
            processTextEvent(appID: appID, event: event)
        }

        // --- Word counting (per-app) ---
        if wordCounters[appID] == nil {
            wordCounters[appID] = WordCounterStateMachine()
        }
        let wordCommitted = wordCounters[appID]!.process(event: event)

        if wordCommitted {
            let fiveMinuteBucket = TimeBucket.start(of: event.timestamp, granularity: .fiveMinutes)
            if isPaste {
                pendingPastedWordsByBucket[fiveMinuteBucket, default: 0] += 1
            } else {
                pendingTypedWordsByBucket[fiveMinuteBucket, default: 0] += 1
            }

            pendingWordIncrements.append(
                WordIncrement(
                    timestamp: event.timestamp,
                    deviceClass: event.deviceClass,
                    appBundleID: event.appBundleID,
                    appName: event.appName
                )
            )
        }

        // --- Legacy active typing tracking (backwards compat) ---
        if let lastTime = lastKeystrokeTime {
            let elapsed = event.timestamp.timeIntervalSince(lastTime)
            if elapsed > 0 && elapsed < config.idleCapFlow {
                let fiveMinuteBucket = TimeBucket.start(of: event.timestamp, granularity: .fiveMinutes)
                pendingActiveTypingByBucket[fiveMinuteBucket, default: 0] += min(elapsed, config.idleCapFlow)
            }
        }
        lastKeystrokeTime = event.timestamp

        // Track paste and edit events (total + per-bucket)
        if isPaste {
            let fiveMinuteBucket = TimeBucket.start(of: event.timestamp, granularity: .fiveMinutes)
            pendingPasteEventsByBucket[fiveMinuteBucket, default: 0] += 1
        }
        if isDelete {
            let fiveMinuteBucket = TimeBucket.start(of: event.timestamp, granularity: .fiveMinutes)
            pendingEditEventsByBucket[fiveMinuteBucket, default: 0] += 1
        }

        if pendingEvents.count >= flushThreshold {
            do {
                try await flushIfNeeded(force: true)
            } catch {
                lastFlushError = error.localizedDescription
            }
        }
    }

    public func snapshot(for timeframe: Timeframe, now: Date = Date()) async throws -> StatsSnapshot {
        var snapshot = try await queryService.snapshot(for: timeframe, now: now)

        guard !pendingEvents.isEmpty || !pendingWordIncrements.isEmpty else {
            return snapshot
        }

        let startDate = timeframe.startDate(now: now)
        let bucketStartDate = startDate.map { TimeBucket.start(of: $0, granularity: .fiveMinutes) }
        let endBucketDate = TimeBucket.start(of: now, granularity: .fiveMinutes)

        let isWithinWindow: (Date) -> Bool = { eventDate in
            guard let startDate else {
                return eventDate <= now
            }
            return eventDate >= startDate && eventDate <= now
        }

        let filteredEvents = pendingEvents.filter { event in
            isWithinWindow(event.timestamp)
        }

        if filteredEvents.isEmpty && pendingWordIncrements.filter({ isWithinWindow($0.timestamp) }).isEmpty {
            return snapshot
        }

        snapshot.totalKeystrokes += filteredEvents.count

        let filteredWords = pendingWordIncrements.filter { increment in
            isWithinWindow(increment.timestamp)
        }
        snapshot.totalWords += filteredWords.count

        // Merge session-based metrics
        snapshot.typedWords += bucketedIntSum(pendingTypedWordsByBucket, from: bucketStartDate, to: endBucketDate)
        snapshot.pastedWordsEst += bucketedIntSum(pendingPastedWordsByBucket, from: bucketStartDate, to: endBucketDate)
        snapshot.pasteEvents += bucketedIntSum(pendingPasteEventsByBucket, from: bucketStartDate, to: endBucketDate)
        snapshot.editEvents += bucketedIntSum(pendingEditEventsByBucket, from: bucketStartDate, to: endBucketDate)
        snapshot.activeSecondsFlow += bucketedDoubleSum(pendingActiveFlowByBucket, from: bucketStartDate, to: endBucketDate)
        snapshot.activeSecondsSkill += bucketedDoubleSum(pendingActiveSkillByBucket, from: bucketStartDate, to: endBucketDate)

        var builtIn = snapshot.deviceBreakdown.builtIn
        var external = snapshot.deviceBreakdown.external
        var unknown = snapshot.deviceBreakdown.unknown

        for event in filteredEvents {
            switch event.deviceClass {
            case .builtIn: builtIn += 1
            case .external: external += 1
            case .unknown: unknown += 1
            }
        }

        snapshot.deviceBreakdown = DeviceBreakdown(builtIn: builtIn, external: external, unknown: unknown)

        var keyCounts = Dictionary(uniqueKeysWithValues: snapshot.keyDistribution.map { ($0.keyCode, $0.count) })
        for event in filteredEvents where KeyboardKeyMapper.isTrackableKeyCode(event.keyCode) {
            keyCounts[event.keyCode, default: 0] += 1
        }

        snapshot.keyDistribution = keyCounts
            .map { keyCode, count in
                TopKeyStat(keyCode: keyCode, keyName: KeyboardKeyMapper.displayName(for: keyCode), count: count)
            }
            .sorted {
                if $0.count == $1.count { return $0.keyCode < $1.keyCode }
                return $0.count > $1.count
            }
        snapshot.topKeys = Array(snapshot.keyDistribution.prefix(8))

        let granularity = timeframe.trendGranularity
        var trendMap = Dictionary(uniqueKeysWithValues: snapshot.trendSeries.map { ($0.bucketStart, $0.count) })
        let trendStartDate = startDate.map {
            TimeBucket.start(of: $0, granularity: granularity, calendar: .current)
        }

        for event in filteredEvents {
            let bucket = TimeBucket.start(of: event.timestamp, granularity: granularity)
            trendMap[bucket, default: 0] += 1
        }

        snapshot.trendSeries = trendMap
            .map { TrendPoint(bucketStart: $0.key, count: $0.value) }
            .sorted { $0.bucketStart < $1.bucketStart }

        snapshot.wpmTrendSeries = mergedWPMTrend(
            existing: snapshot.wpmTrendSeries,
            increments: filteredWords,
            granularity: granularity
        )

        snapshot.topAppsByWords = mergedTopApps(
            existing: snapshot.topAppsByWords,
            increments: filteredWords
        )

        snapshot.typingSpeedTrendSeries = mergedTypingSpeedTrend(
            existing: snapshot.typingSpeedTrendSeries,
            wordIncrements: filteredWords,
            activeTypingByBucket: pendingActiveTypingByBucket,
            activeFlowByBucket: pendingActiveFlowByBucket,
            activeSkillByBucket: pendingActiveSkillByBucket,
            granularity: granularity,
            startDate: trendStartDate,
            endDate: now
        )

        return snapshot
    }

    // MARK: - Session Management

    private func startSession(appID: String, appName: String, event: KeyEvent) {
        sessions[appID] = TypingSession(
            appBundleID: appID,
            appName: appName,
            startTime: event.timestamp,
            monotonicTime: event.monotonicTime
        )
        lastTextEventMonotonic[appID] = event.monotonicTime
        lastTextEventWallClock[appID] = event.timestamp
    }

    private func endSession(forApp appID: String) {
        // Flush last word if currently in a word
        if var counter = wordCounters[appID] {
            if counter.flushLastWord() {
                if let session = sessions[appID] {
                    let bucket = TimeBucket.start(of: session.lastTextEventTime, granularity: .fiveMinutes)
                    pendingTypedWordsByBucket[bucket, default: 0] += 1

                    pendingWordIncrements.append(
                        WordIncrement(
                            timestamp: session.lastTextEventTime,
                            deviceClass: .unknown,
                            appBundleID: session.appBundleID,
                            appName: session.appName
                        )
                    )
                }
            }
            wordCounters[appID] = counter
        }

        sessions.removeValue(forKey: appID)
        lastTextEventMonotonic.removeValue(forKey: appID)
        lastTextEventWallClock.removeValue(forKey: appID)
    }

    private func endAllSessions() {
        let appIDs = Array(sessions.keys)
        for appID in appIDs {
            endSession(forApp: appID)
        }
    }

    // MARK: - Text Event Processing

    private func processTextEvent(appID: String, event: KeyEvent) {
        guard let lastMono = lastTextEventMonotonic[appID],
              let lastWall = lastTextEventWallClock[appID] else {
            // First text event in this session
            lastTextEventMonotonic[appID] = event.monotonicTime
            lastTextEventWallClock[appID] = event.timestamp
            sessions[appID]?.lastMonotonicTime = event.monotonicTime
            sessions[appID]?.lastTextEventTime = event.timestamp
            return
        }

        // Use monotonic time for accurate delta (survives sleep/wake)
        let dt = event.monotonicTime - lastMono
        guard dt > 0 else {
            lastTextEventMonotonic[appID] = event.monotonicTime
            lastTextEventWallClock[appID] = event.timestamp
            sessions[appID]?.lastMonotonicTime = event.monotonicTime
            sessions[appID]?.lastTextEventTime = event.timestamp
            return
        }

        // Flow active time: min(dt, idle_cap_flow)
        let flowDelta = min(dt, config.idleCapFlow)
        // Skill active time: min(dt, idle_cap_skill)
        let skillDelta = min(dt, config.idleCapSkill)

        // Split across hour boundaries for bucket assignment
        let startWall = lastWall
        let endWall = event.timestamp
        let intervals = splitAcrossTimeBoundaries(
            startWall: startWall,
            endWall: endWall,
            flowDelta: flowDelta,
            skillDelta: skillDelta
        )

        for interval in intervals {
            pendingActiveFlowByBucket[interval.bucket, default: 0] += interval.flowSeconds
            pendingActiveSkillByBucket[interval.bucket, default: 0] += interval.skillSeconds
            // Legacy compat
            pendingActiveTypingByBucket[interval.bucket, default: 0] += interval.flowSeconds
        }

        lastTextEventMonotonic[appID] = event.monotonicTime
        lastTextEventWallClock[appID] = event.timestamp
        sessions[appID]?.lastMonotonicTime = event.monotonicTime
        sessions[appID]?.lastTextEventTime = event.timestamp
    }

    /// Split time deltas across fixed boundaries so each bucket gets its share.
    private func splitAcrossTimeBoundaries(
        startWall: Date,
        endWall: Date,
        flowDelta: Double,
        skillDelta: Double
    ) -> [(bucket: Date, flowSeconds: Double, skillSeconds: Double)] {
        let startBucket = TimeBucket.start(of: startWall, granularity: .fiveMinutes)
        let endBucket = TimeBucket.start(of: endWall, granularity: .fiveMinutes)

        if startBucket == endBucket {
            return [(bucket: startBucket, flowSeconds: flowDelta, skillSeconds: skillDelta)]
        }

        // Cross-boundary: apportion by wall-clock ratio
        let totalWallDelta = endWall.timeIntervalSince(startWall)
        guard totalWallDelta > 0 else {
            return [(bucket: endBucket, flowSeconds: flowDelta, skillSeconds: skillDelta)]
        }

        var results: [(bucket: Date, flowSeconds: Double, skillSeconds: Double)] = []
        var cursor = startBucket
        var prevBoundary = startWall

        while cursor <= endBucket {
            let nextBoundary = TimeBucket.advance(cursor, by: .fiveMinutes)
            let boundary = min(nextBoundary, endWall)
            let fraction = boundary.timeIntervalSince(prevBoundary) / totalWallDelta

            results.append((
                bucket: cursor,
                flowSeconds: flowDelta * fraction,
                skillSeconds: skillDelta * fraction
            ))

            prevBoundary = boundary
            cursor = nextBoundary
            if cursor > endBucket { break }
        }

        return results
    }

    // MARK: - Trend Merging

    private func mergedWPMTrend(
        existing: [WPMTrendPoint],
        increments: [WordIncrement],
        granularity: TimeBucketGranularity
    ) -> [WPMTrendPoint] {
        var wordsByBucket = Dictionary(uniqueKeysWithValues: existing.map { ($0.bucketStart, $0.words) })

        for increment in increments {
            let bucket = TimeBucket.start(of: increment.timestamp, granularity: granularity)
            wordsByBucket[bucket, default: 0] += 1
        }

        return wordsByBucket
            .map { bucketStart, words in
                WPMTrendPoint(
                    bucketStart: bucketStart,
                    words: words,
                    rate: Double(words) / granularity.bucketMinutes
                )
            }
            .sorted { $0.bucketStart < $1.bucketStart }
    }

    private func mergedTopApps(
        existing: [AppWordStat],
        increments: [WordIncrement]
    ) -> [AppWordStat] {
        var byBundleID = Dictionary(uniqueKeysWithValues: existing.map { ($0.bundleID, $0) })

        for increment in increments {
            let identity = AppIdentity.normalize(bundleID: increment.appBundleID, appName: increment.appName)
            let existingCount = byBundleID[identity.bundleID]?.wordCount ?? 0
            byBundleID[identity.bundleID] = AppWordStat(
                bundleID: identity.bundleID,
                appName: identity.appName,
                wordCount: existingCount + 1
            )
        }

        return byBundleID.values.sorted {
            if $0.wordCount == $1.wordCount {
                return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }
            return $0.wordCount > $1.wordCount
        }
    }

    private func mergedTypingSpeedTrend(
        existing: [TypingSpeedTrendPoint],
        wordIncrements: [WordIncrement],
        activeTypingByBucket: [Date: Double],
        activeFlowByBucket: [Date: Double],
        activeSkillByBucket: [Date: Double],
        granularity: TimeBucketGranularity,
        startDate: Date?,
        endDate: Date
    ) -> [TypingSpeedTrendPoint] {
        var wordsByBucket: [Date: Int] = [:]
        var secondsByBucket: [Date: Double] = [:]
        var flowByBucket: [Date: Double] = [:]
        var skillByBucket: [Date: Double] = [:]
        let endBucketDate = TimeBucket.start(of: endDate, granularity: granularity)

        for point in existing {
            wordsByBucket[point.bucketStart] = point.words
            secondsByBucket[point.bucketStart] = point.activeSeconds
            flowByBucket[point.bucketStart] = point.activeSecondsFlow
            skillByBucket[point.bucketStart] = point.activeSecondsSkill
        }

        for increment in wordIncrements {
            let bucket = TimeBucket.start(of: increment.timestamp, granularity: granularity)
            guard bucket <= endBucketDate else { continue }
            wordsByBucket[bucket, default: 0] += 1
        }

        for (hourBucket, seconds) in activeTypingByBucket {
            if let startDate, hourBucket < startDate { continue }
            if hourBucket > endBucketDate { continue }
            let bucket = TimeBucket.start(of: hourBucket, granularity: granularity)
            secondsByBucket[bucket, default: 0] += seconds
        }

        for (hourBucket, seconds) in activeFlowByBucket {
            if let startDate, hourBucket < startDate { continue }
            if hourBucket > endBucketDate { continue }
            let bucket = TimeBucket.start(of: hourBucket, granularity: granularity)
            flowByBucket[bucket, default: 0] += seconds
        }

        for (hourBucket, seconds) in activeSkillByBucket {
            if let startDate, hourBucket < startDate { continue }
            if hourBucket > endBucketDate { continue }
            let bucket = TimeBucket.start(of: hourBucket, granularity: granularity)
            skillByBucket[bucket, default: 0] += seconds
        }

        let allBuckets = Set(wordsByBucket.keys)
            .union(secondsByBucket.keys)
            .union(flowByBucket.keys)
            .union(skillByBucket.keys)

        return allBuckets
            .map { bucket in
                TypingSpeedTrendPoint(
                    bucketStart: bucket,
                    words: wordsByBucket[bucket, default: 0],
                    activeSeconds: secondsByBucket[bucket, default: 0],
                    activeSecondsFlow: flowByBucket[bucket, default: 0],
                    activeSecondsSkill: skillByBucket[bucket, default: 0]
                )
            }
            .sorted { $0.bucketStart < $1.bucketStart }
    }

    // MARK: - Flush

    private func flushIfNeeded(force: Bool) async throws {
        guard force || pendingEvents.count >= flushThreshold else { return }
        guard !pendingEvents.isEmpty || !pendingWordIncrements.isEmpty ||
            !pendingActiveTypingByBucket.isEmpty || !pendingActiveFlowByBucket.isEmpty || !pendingActiveSkillByBucket.isEmpty else {
            return
        }

        let events = pendingEvents
        let wordIncrements = pendingWordIncrements

        // Collect all buckets that have any data
        let allBuckets = Set(pendingActiveTypingByBucket.keys)
            .union(pendingActiveFlowByBucket.keys)
            .union(pendingActiveSkillByBucket.keys)
            .union(pendingTypedWordsByBucket.keys)
            .union(pendingPastedWordsByBucket.keys)
            .union(pendingPasteEventsByBucket.keys)
            .union(pendingEditEventsByBucket.keys)

        let activeTypingIncrements = allBuckets.map { bucket in
            ActiveTypingIncrement(
                bucketStart: bucket,
                activeSeconds: pendingActiveTypingByBucket[bucket] ?? 0,
                activeSecondsFlow: pendingActiveFlowByBucket[bucket] ?? pendingActiveTypingByBucket[bucket] ?? 0,
                activeSecondsSkill: pendingActiveSkillByBucket[bucket] ?? pendingActiveTypingByBucket[bucket] ?? 0,
                typedWords: pendingTypedWordsByBucket[bucket] ?? 0,
                pastedWordsEst: pendingPastedWordsByBucket[bucket] ?? 0,
                pasteEvents: pendingPasteEventsByBucket[bucket] ?? 0,
                editEvents: pendingEditEventsByBucket[bucket] ?? 0
            )
        }
        try await store.flush(
            events: events,
            wordIncrements: wordIncrements,
            activeTypingIncrements: activeTypingIncrements
        )
        totalFlushes += 1
        totalFlushedEvents += events.count
        lastFlushAt = Date()
        lastFlushError = nil
        pendingEvents.removeAll(keepingCapacity: true)
        pendingWordIncrements.removeAll(keepingCapacity: true)
        pendingActiveTypingByBucket.removeAll(keepingCapacity: true)
        pendingActiveFlowByBucket.removeAll(keepingCapacity: true)
        pendingActiveSkillByBucket.removeAll(keepingCapacity: true)
        pendingTypedWordsByBucket.removeAll(keepingCapacity: true)
        pendingPastedWordsByBucket.removeAll(keepingCapacity: true)
        pendingPasteEventsByBucket.removeAll(keepingCapacity: true)
        pendingEditEventsByBucket.removeAll(keepingCapacity: true)
    }

    private func shouldCountEventInWordStats(_ event: KeyEvent) -> Bool {
        guard event.isTextProducing else { return false }

        return !shouldSuppressWordCounting(
            bundleID: event.appBundleID,
            appName: event.appName
        )
    }

    private func shouldSuppressWordCounting(bundleID: String?, appName: String?) -> Bool {
        let normalizedBundleID = normalizeForSuppression(bundleID)
        let normalizedAppName = normalizeForSuppression(appName)

        if hasSuppressionMatch(
            source: normalizedBundleID,
            compactSource: normalizedBundleID.replacingOccurrences(of: " ", with: ""),
            ignored: ignoredWordCountBundleSuffixes
        ) {
            return true
        }

        return hasSuppressionMatch(
            source: normalizedAppName,
            compactSource: normalizedAppName.replacingOccurrences(of: " ", with: ""),
            ignored: ignoredWordCountAppNameFragments
        )
    }

    private func normalizeForSuppression(_ value: String?) -> String {
        guard let value else { return "" }

        let lowered = value.lowercased()
        let alphaNumericAndSpace = lowered.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: " ",
            options: .regularExpression
        )

        return alphaNumericAndSpace
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func hasSuppressionMatch(
        source: String,
        compactSource: String,
        ignored: Set<String>
    ) -> Bool {
        guard !source.isEmpty else { return false }

        for token in ignored where !token.isEmpty {
            if source.contains(token) {
                return true
            }

            let compactToken = token.replacingOccurrences(of: " ", with: "")
            if !compactToken.isEmpty && compactSource.contains(compactToken) {
                return true
            }
        }

        return false
    }

    private func clearWordCountState(for appID: String, event: KeyEvent) {
        wordCounters[appID]?.reset()
        lastTextEventMonotonic.removeValue(forKey: appID)
        lastTextEventWallClock.removeValue(forKey: appID)
        if var session = sessions[appID] {
            session.lastMonotonicTime = event.monotonicTime
            session.lastTextEventTime = event.timestamp
            sessions[appID] = session
        }
    }

    private func bucketedIntSum(_ valuesByBucket: [Date: Int], from startDate: Date?, to endDate: Date) -> Int {
        let endBucket = TimeBucket.start(of: endDate, granularity: .fiveMinutes)
        guard let startDate else {
            return valuesByBucket.reduce(into: 0) { total, entry in
                if entry.key <= endBucket {
                    total += entry.value
                }
            }
        }

        return valuesByBucket.reduce(into: 0) { total, entry in
            if entry.key >= startDate && entry.key <= endBucket {
                total += entry.value
            }
        }
    }

    private func bucketedDoubleSum(_ valuesByBucket: [Date: Double], from startDate: Date?, to endDate: Date) -> Double {
        let endBucket = TimeBucket.start(of: endDate, granularity: .fiveMinutes)
        guard let startDate else {
            return valuesByBucket.reduce(into: 0.0) { total, entry in
                if entry.key <= endBucket {
                    total += entry.value
                }
            }
        }

        return valuesByBucket.reduce(into: 0.0) { total, entry in
            if entry.key >= startDate && entry.key <= endBucket {
                total += entry.value
            }
        }
    }
}
