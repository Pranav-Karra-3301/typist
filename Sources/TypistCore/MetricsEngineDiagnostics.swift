import Foundation

public struct MetricsEngineDiagnostics: Sendable, Hashable {
    public let isStarted: Bool
    public let pendingEvents: Int
    public let pendingWordIncrements: Int
    public let totalIngestedEvents: Int
    public let totalFlushes: Int
    public let totalFlushedEvents: Int
    public let lastIngestAt: Date?
    public let lastFlushAt: Date?
    public let lastFlushError: String?

    public init(
        isStarted: Bool,
        pendingEvents: Int,
        pendingWordIncrements: Int,
        totalIngestedEvents: Int,
        totalFlushes: Int,
        totalFlushedEvents: Int,
        lastIngestAt: Date?,
        lastFlushAt: Date?,
        lastFlushError: String?
    ) {
        self.isStarted = isStarted
        self.pendingEvents = pendingEvents
        self.pendingWordIncrements = pendingWordIncrements
        self.totalIngestedEvents = totalIngestedEvents
        self.totalFlushes = totalFlushes
        self.totalFlushedEvents = totalFlushedEvents
        self.lastIngestAt = lastIngestAt
        self.lastFlushAt = lastFlushAt
        self.lastFlushError = lastFlushError
    }
}
