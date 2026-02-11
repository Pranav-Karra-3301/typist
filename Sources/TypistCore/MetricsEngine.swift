import Foundation

public actor MetricsEngine {
    private let store: PersistenceWriting
    private let queryService: StatsQuerying
    private var wordCounter = WordCounterStateMachine()

    private var pendingEvents: [KeyEvent] = []
    private var pendingWordIncrements: [WordIncrement] = []

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

        if wordCounter.process(event: event) {
            pendingWordIncrements.append(WordIncrement(timestamp: event.timestamp, deviceClass: event.deviceClass))
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

        guard !pendingEvents.isEmpty else {
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

        let granularity = timeframe.trendGranularity
        var trendMap = Dictionary(uniqueKeysWithValues: snapshot.trendSeries.map { ($0.bucketStart, $0.count) })

        for event in filteredEvents {
            let bucket = TimeBucket.start(of: event.timestamp, granularity: granularity)
            trendMap[bucket, default: 0] += 1
        }

        snapshot.trendSeries = trendMap
            .map { TrendPoint(bucketStart: $0.key, count: $0.value) }
            .sorted { $0.bucketStart < $1.bucketStart }

        return snapshot
    }

    private func flushIfNeeded(force: Bool) async throws {
        guard force || pendingEvents.count >= flushThreshold else { return }
        guard !pendingEvents.isEmpty || !pendingWordIncrements.isEmpty else { return }

        let events = pendingEvents
        let wordIncrements = pendingWordIncrements

        try await store.flush(events: events, wordIncrements: wordIncrements)
        totalFlushes += 1
        totalFlushedEvents += events.count
        lastFlushAt = Date()
        lastFlushError = nil
        pendingEvents.removeAll(keepingCapacity: true)
        pendingWordIncrements.removeAll(keepingCapacity: true)
    }
}
