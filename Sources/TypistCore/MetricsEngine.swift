import Foundation

public actor MetricsEngine {
    private let store: PersistenceWriting
    private let queryService: StatsQuerying
    private var wordCounter = WordCounterStateMachine()

    private var pendingEvents: [KeyEvent] = []
    private var pendingWordIncrements: [WordIncrement] = []
    
    // Active typing tracking: time between keystrokes < 5 seconds counts as active
    private static let activeTypingThreshold: TimeInterval = 5.0
    private var lastKeystrokeTime: Date?
    private var pendingActiveTypingByBucket: [Date: Double] = [:] // bucket -> seconds

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

    public init(
        store: PersistenceWriting,
        queryService: StatsQuerying,
        flushInterval: Duration = .seconds(5),
        flushThreshold: Int = 200
    ) {
        self.store = store
        self.queryService = queryService
        self.flushInterval = flushInterval
        self.flushThreshold = flushThreshold
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
        lastKeystrokeTime = nil
        wordCounter.reset()
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
        pendingEvents.append(event)
        totalIngestedEvents += 1
        lastIngestAt = event.timestamp

        // Track active typing time: if keystroke is within threshold of last one, count elapsed time
        if let lastTime = lastKeystrokeTime {
            let elapsed = event.timestamp.timeIntervalSince(lastTime)
            if elapsed > 0 && elapsed < Self.activeTypingThreshold {
                // This keystroke is part of active typing - add elapsed time to hourly bucket
                let hourBucket = TimeBucket.startOfHour(for: event.timestamp)
                pendingActiveTypingByBucket[hourBucket, default: 0] += elapsed
            }
        }
        lastKeystrokeTime = event.timestamp

        if wordCounter.process(event: event) {
            pendingWordIncrements.append(
                WordIncrement(
                    timestamp: event.timestamp,
                    deviceClass: event.deviceClass,
                    appBundleID: event.appBundleID,
                    appName: event.appName
                )
            )
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
        let filteredEvents = pendingEvents.filter { event in
            guard let startDate else { return true }
            return event.timestamp >= startDate
        }

        if filteredEvents.isEmpty {
            return snapshot
        }

        snapshot.totalKeystrokes += filteredEvents.count

        let filteredWords = pendingWordIncrements.filter { increment in
            guard let startDate else { return true }
            return increment.timestamp >= startDate
        }
        snapshot.totalWords += filteredWords.count

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
            granularity: granularity,
            startDate: startDate
        )

        return snapshot
    }

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
        granularity: TimeBucketGranularity,
        startDate: Date?
    ) -> [TypingSpeedTrendPoint] {
        // Build maps from existing data
        var wordsByBucket: [Date: Int] = [:]
        var secondsByBucket: [Date: Double] = [:]
        
        for point in existing {
            wordsByBucket[point.bucketStart] = point.words
            secondsByBucket[point.bucketStart] = point.activeSeconds
        }

        // Add pending word increments
        for increment in wordIncrements {
            let bucket = TimeBucket.start(of: increment.timestamp, granularity: granularity)
            wordsByBucket[bucket, default: 0] += 1
        }

        // Add pending active typing (convert hourly buckets to requested granularity if needed)
        for (hourBucket, seconds) in activeTypingByBucket {
            // Filter by start date
            if let startDate, hourBucket < startDate {
                continue
            }
            let bucket = TimeBucket.start(of: hourBucket, granularity: granularity)
            secondsByBucket[bucket, default: 0] += seconds
        }

        // Combine into trend points
        let allBuckets = Set(wordsByBucket.keys).union(secondsByBucket.keys)
        return allBuckets
            .map { bucket in
                TypingSpeedTrendPoint(
                    bucketStart: bucket,
                    words: wordsByBucket[bucket, default: 0],
                    activeSeconds: secondsByBucket[bucket, default: 0]
                )
            }
            .sorted { $0.bucketStart < $1.bucketStart }
    }

    private func flushIfNeeded(force: Bool) async throws {
        guard force || pendingEvents.count >= flushThreshold else { return }
        guard !pendingEvents.isEmpty || !pendingWordIncrements.isEmpty || !pendingActiveTypingByBucket.isEmpty else { return }

        let events = pendingEvents
        let wordIncrements = pendingWordIncrements
        let activeTypingIncrements = pendingActiveTypingByBucket.map { bucket, seconds in
            ActiveTypingIncrement(bucketStart: bucket, activeSeconds: seconds)
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
    }
}
