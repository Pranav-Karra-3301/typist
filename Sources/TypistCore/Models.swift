import Foundation

public enum DeviceClass: String, Codable, CaseIterable, Sendable {
    case builtIn = "built_in"
    case external
    case unknown
}

public enum AppIdentity {
    public static let unknownBundleID = "unknown.app"
    public static let unknownAppName = "Unknown App"

    public static func normalize(bundleID: String?, appName: String?) -> (bundleID: String, appName: String) {
        let normalizedBundleID: String
        if let bundleID, !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalizedBundleID = bundleID
        } else {
            normalizedBundleID = unknownBundleID
        }

        let normalizedAppName: String
        if let appName, !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalizedAppName = appName
        } else if normalizedBundleID != unknownBundleID {
            normalizedAppName = normalizedBundleID
        } else {
            normalizedAppName = unknownAppName
        }

        return (normalizedBundleID, normalizedAppName)
    }
}

public enum TimeBucketGranularity: Sendable {
    case fiveMinutes
    case hour
    case day

    public var bucketMinutes: Double {
        switch self {
        case .fiveMinutes: return 5
        case .hour: return 60
        case .day: return 1_440
        }
    }
}

public enum Timeframe: String, CaseIterable, Sendable {
    case h1
    case h12
    case h24
    case d7
    case d30
    case all

    public var title: String {
        switch self {
        case .h1: return "1H"
        case .h12: return "12H"
        case .h24: return "24H"
        case .d7: return "7D"
        case .d30: return "30D"
        case .all: return "All"
        }
    }

    public var trendGranularity: TimeBucketGranularity {
        switch self {
        case .h1:
            return .fiveMinutes
        case .h12, .h24:
            return .hour
        case .d7, .d30, .all:
            return .day
        }
    }

    public func startDate(now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .h1:
            return calendar.date(byAdding: .hour, value: -1, to: now)
        case .h12:
            return calendar.date(byAdding: .hour, value: -12, to: now)
        case .h24:
            return calendar.date(byAdding: .hour, value: -24, to: now)
        case .d7:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .d30:
            return calendar.date(byAdding: .day, value: -30, to: now)
        case .all:
            return nil
        }
    }
}

public enum TimeBucket {
    public static func start(of date: Date, granularity: TimeBucketGranularity, calendar: Calendar = .current) -> Date {
        switch granularity {
        case .fiveMinutes:
            return startOfFiveMinutes(for: date, calendar: calendar)
        case .hour:
            return startOfHour(for: date, calendar: calendar)
        case .day:
            return startOfDay(for: date, calendar: calendar)
        }
    }

    public static func startOfFiveMinutes(for date: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = components.minute ?? 0
        components.minute = (minute / 5) * 5
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components) ?? date
    }

    public static func startOfHour(for date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return calendar.date(from: components) ?? date
    }

    public static func startOfDay(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func advance(_ date: Date, by granularity: TimeBucketGranularity, calendar: Calendar = .current) -> Date {
        switch granularity {
        case .fiveMinutes:
            return calendar.date(byAdding: .minute, value: 5, to: date) ?? date
        case .hour:
            return calendar.date(byAdding: .hour, value: 1, to: date) ?? date
        case .day:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
    }
}

public struct KeyEvent: Sendable, Hashable {
    public let timestamp: Date
    /// Monotonic uptime (ProcessInfo.systemUptime) for accurate delta computation across sleep/wake.
    public let monotonicTime: TimeInterval
    public let keyCode: Int
    public let isSeparator: Bool
    public let isTextProducing: Bool
    /// Whether this event should contribute to word-count and WPM calculations.
    public let isCountedForWordStats: Bool
    public let deviceClass: DeviceClass
    public let appBundleID: String?
    public let appName: String?
    /// True if this keystroke is part of a paste chord (Cmd+V detected).
    public let isPasteChord: Bool

    public init(
        timestamp: Date,
        keyCode: Int,
        isSeparator: Bool,
        deviceClass: DeviceClass,
        appBundleID: String? = nil,
        appName: String? = nil,
        monotonicTime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        isTextProducing: Bool? = nil,
        isCountedForWordStats: Bool = true,
        isPasteChord: Bool = false
    ) {
        self.timestamp = timestamp
        self.monotonicTime = monotonicTime
        self.keyCode = keyCode
        self.isSeparator = isSeparator
        self.isTextProducing = isTextProducing ?? KeyboardKeyMapper.isTextProducingKey(keyCode)
        self.isCountedForWordStats = isCountedForWordStats
        self.deviceClass = deviceClass
        self.appBundleID = appBundleID
        self.appName = appName
        self.isPasteChord = isPasteChord
    }

    public func withWordCounting(_ isCountedForWordStats: Bool) -> KeyEvent {
        KeyEvent(
            timestamp: timestamp,
            keyCode: keyCode,
            isSeparator: isSeparator,
            deviceClass: deviceClass,
            appBundleID: appBundleID,
            appName: appName,
            monotonicTime: monotonicTime,
            isTextProducing: isTextProducing,
            isCountedForWordStats: isCountedForWordStats,
            isPasteChord: isPasteChord
        )
    }
}

// MARK: - Session Configuration

public struct SessionConfig: Sendable {
    /// Max idle gap before starting a new session (seconds).
    public let sessionTimeout: TimeInterval
    /// Max gap counted as "active flow typing" (includes short thinking pauses).
    public let idleCapFlow: TimeInterval
    /// Max gap counted as "active skill typing" (mostly finger speed).
    public let idleCapSkill: TimeInterval

    public static let `default` = SessionConfig(
        sessionTimeout: 60,
        idleCapFlow: 12,
        idleCapSkill: 2
    )

    public init(sessionTimeout: TimeInterval, idleCapFlow: TimeInterval, idleCapSkill: TimeInterval) {
        self.sessionTimeout = sessionTimeout
        self.idleCapFlow = idleCapFlow
        self.idleCapSkill = idleCapSkill
    }
}

// MARK: - Session State

/// Represents a per-app typing session.
public struct TypingSession: Sendable {
    public let appBundleID: String
    public let appName: String
    public var lastTextEventTime: Date
    public var lastMonotonicTime: TimeInterval

    public init(
        appBundleID: String,
        appName: String,
        startTime: Date,
        monotonicTime: TimeInterval
    ) {
        self.appBundleID = appBundleID
        self.appName = appName
        self.lastTextEventTime = startTime
        self.lastMonotonicTime = monotonicTime
    }
}

public struct WordIncrement: Sendable, Hashable {
    public let timestamp: Date
    public let deviceClass: DeviceClass
    public let appBundleID: String?
    public let appName: String?

    public init(
        timestamp: Date,
        deviceClass: DeviceClass,
        appBundleID: String? = nil,
        appName: String? = nil
    ) {
        self.timestamp = timestamp
        self.deviceClass = deviceClass
        self.appBundleID = appBundleID
        self.appName = appName
    }
}

public struct TrendPoint: Sendable, Hashable, Identifiable {
    public let bucketStart: Date
    public let count: Int

    public var id: TimeInterval { bucketStart.timeIntervalSince1970 }

    public init(bucketStart: Date, count: Int) {
        self.bucketStart = bucketStart
        self.count = count
    }
}

public struct WPMTrendPoint: Sendable, Hashable, Identifiable {
    public let bucketStart: Date
    public let words: Int
    public let rate: Double

    public var id: TimeInterval { bucketStart.timeIntervalSince1970 }

    public init(bucketStart: Date, words: Int, rate: Double) {
        self.bucketStart = bucketStart
        self.words = words
        self.rate = rate
    }
}

public struct TypingSpeedTrendPoint: Sendable, Hashable, Identifiable {
    public let bucketStart: Date
    public let words: Int
    public let activeSeconds: Double
    public let activeSecondsFlow: Double
    public let activeSecondsSkill: Double
    public let wpm: Double
    public let flowWPM: Double
    public let skillWPM: Double

    public var id: TimeInterval { bucketStart.timeIntervalSince1970 }

    /// Minimum active seconds in a bucket before WPM is meaningful.
    private static let minActiveSecondsForWPM: Double = 5.0
    /// Hard caps to prevent absurd spikes from noisy buckets.
    private static let maxFlowWPM: Double = 200.0
    private static let maxSkillWPM: Double = 300.0

    public init(
        bucketStart: Date,
        words: Int,
        activeSeconds: Double,
        activeSecondsFlow: Double = 0,
        activeSecondsSkill: Double = 0
    ) {
        self.bucketStart = bucketStart
        self.words = words
        self.activeSeconds = activeSeconds
        self.activeSecondsFlow = activeSecondsFlow > 0 ? activeSecondsFlow : activeSeconds
        self.activeSecondsSkill = activeSecondsSkill > 0 ? activeSecondsSkill : activeSeconds

        let rawWPM = activeSeconds > 0 ? Double(words) / (activeSeconds / 60.0) : 0
        self.wpm = min(rawWPM, Self.maxFlowWPM)

        if self.activeSecondsFlow >= Self.minActiveSecondsForWPM {
            self.flowWPM = min(Double(words) / (self.activeSecondsFlow / 60.0), Self.maxFlowWPM)
        } else {
            self.flowWPM = 0
        }

        if self.activeSecondsSkill >= Self.minActiveSecondsForWPM {
            self.skillWPM = min(Double(words) / (self.activeSecondsSkill / 60.0), Self.maxSkillWPM)
        } else {
            self.skillWPM = 0
        }
    }
}

public struct ActiveTypingIncrement: Sendable, Hashable {
    public let bucketStart: Date
    public let activeSeconds: Double
    public let activeSecondsFlow: Double
    public let activeSecondsSkill: Double
    public let typedWords: Int
    public let pastedWordsEst: Int
    public let pasteEvents: Int
    public let editEvents: Int

    public init(
        bucketStart: Date,
        activeSeconds: Double,
        activeSecondsFlow: Double = 0,
        activeSecondsSkill: Double = 0,
        typedWords: Int = 0,
        pastedWordsEst: Int = 0,
        pasteEvents: Int = 0,
        editEvents: Int = 0
    ) {
        self.bucketStart = bucketStart
        self.activeSeconds = activeSeconds
        self.activeSecondsFlow = activeSecondsFlow > 0 ? activeSecondsFlow : activeSeconds
        self.activeSecondsSkill = activeSecondsSkill > 0 ? activeSecondsSkill : activeSeconds
        self.typedWords = typedWords
        self.pastedWordsEst = pastedWordsEst
        self.pasteEvents = pasteEvents
        self.editEvents = editEvents
    }
}

public struct AppWordStat: Sendable, Hashable, Identifiable {
    public let bundleID: String
    public let appName: String
    public let wordCount: Int

    public var id: String { bundleID }

    public init(bundleID: String, appName: String, wordCount: Int) {
        self.bundleID = bundleID
        self.appName = appName
        self.wordCount = wordCount
    }
}

public struct TopKeyStat: Sendable, Hashable, Identifiable {
    public let keyCode: Int
    public let keyName: String
    public let count: Int

    public var id: Int { keyCode }

    public init(keyCode: Int, keyName: String, count: Int) {
        self.keyCode = keyCode
        self.keyName = keyName
        self.count = count
    }
}

public struct DeviceBreakdown: Sendable, Hashable {
    public let builtIn: Int
    public let external: Int
    public let unknown: Int

    public init(builtIn: Int, external: Int, unknown: Int) {
        self.builtIn = builtIn
        self.external = external
        self.unknown = unknown
    }
}

public struct StatsSnapshot: Sendable, Hashable {
    public let timeframe: Timeframe
    public var totalKeystrokes: Int
    public var totalWords: Int
    public var typedWords: Int
    public var pastedWordsEst: Int
    public var pasteEvents: Int
    public var editEvents: Int
    public var activeSecondsFlow: Double
    public var activeSecondsSkill: Double
    public var deviceBreakdown: DeviceBreakdown
    public var keyDistribution: [TopKeyStat]
    public var topKeys: [TopKeyStat]
    public var trendSeries: [TrendPoint]
    public var wpmTrendSeries: [WPMTrendPoint]
    public var typingSpeedTrendSeries: [TypingSpeedTrendPoint]
    public var topAppsByWords: [AppWordStat]

    /// Flow WPM: typed_words / (active_seconds_flow / 60). Includes short think pauses.
    /// Falls back to totalWords when typed_words is unavailable (pre-migration data).
    public var flowWPM: Double {
        guard activeSecondsFlow > 0 else { return 0 }
        let words = typedWords > 0 ? typedWords : totalWords
        return min(Double(words) / (activeSecondsFlow / 60.0), 200)
    }

    /// Skill WPM: typed_words / (active_seconds_skill / 60). Finger speed only.
    public var skillWPM: Double {
        guard activeSecondsSkill > 0 else { return 0 }
        let words = typedWords > 0 ? typedWords : totalWords
        return min(Double(words) / (activeSecondsSkill / 60.0), 300)
    }

    /// Assisted WPM: includes paste-estimated words in flow time.
    public var assistedWPM: Double {
        guard activeSecondsFlow > 0 else { return 0 }
        let words = typedWords > 0 ? (typedWords + pastedWordsEst) : totalWords
        return min(Double(words) / (activeSecondsFlow / 60.0), 200)
    }

    /// Edit ratio: deleted_events / total_events (approximate).
    public var editRatio: Double {
        let total = totalKeystrokes
        guard total > 0 else { return 0 }
        return Double(editEvents) / Double(total)
    }

    public init(
        timeframe: Timeframe,
        totalKeystrokes: Int,
        totalWords: Int,
        typedWords: Int = 0,
        pastedWordsEst: Int = 0,
        pasteEvents: Int = 0,
        editEvents: Int = 0,
        activeSecondsFlow: Double = 0,
        activeSecondsSkill: Double = 0,
        deviceBreakdown: DeviceBreakdown,
        keyDistribution: [TopKeyStat],
        topKeys: [TopKeyStat],
        trendSeries: [TrendPoint],
        wpmTrendSeries: [WPMTrendPoint] = [],
        typingSpeedTrendSeries: [TypingSpeedTrendPoint] = [],
        topAppsByWords: [AppWordStat] = []
    ) {
        self.timeframe = timeframe
        self.totalKeystrokes = totalKeystrokes
        self.totalWords = totalWords
        self.typedWords = typedWords
        self.pastedWordsEst = pastedWordsEst
        self.pasteEvents = pasteEvents
        self.editEvents = editEvents
        self.activeSecondsFlow = activeSecondsFlow
        self.activeSecondsSkill = activeSecondsSkill
        self.deviceBreakdown = deviceBreakdown
        self.keyDistribution = keyDistribution
        self.topKeys = topKeys
        self.trendSeries = trendSeries
        self.wpmTrendSeries = wpmTrendSeries
        self.typingSpeedTrendSeries = typingSpeedTrendSeries
        self.topAppsByWords = topAppsByWords
    }

    public static func empty(timeframe: Timeframe) -> StatsSnapshot {
        StatsSnapshot(
            timeframe: timeframe,
            totalKeystrokes: 0,
            totalWords: 0,
            typedWords: 0,
            pastedWordsEst: 0,
            pasteEvents: 0,
            editEvents: 0,
            activeSecondsFlow: 0,
            activeSecondsSkill: 0,
            deviceBreakdown: DeviceBreakdown(builtIn: 0, external: 0, unknown: 0),
            keyDistribution: [],
            topKeys: [],
            trendSeries: [],
            wpmTrendSeries: [],
            typingSpeedTrendSeries: [],
            topAppsByWords: []
        )
    }
}

public protocol KeyboardCaptureProviding {
    var events: AsyncStream<KeyEvent> { get }
    func start() throws
    func stop()
}

/// Aggregated session metrics for flushing to persistence.
public protocol PersistenceWriting: Sendable {
    func flush(
        events: [KeyEvent],
        wordIncrements: [WordIncrement],
        activeTypingIncrements: [ActiveTypingIncrement]
    ) async throws
}

public protocol StatsQuerying: Sendable {
    func snapshot(for timeframe: Timeframe, now: Date) async throws -> StatsSnapshot
}

public protocol StatsResetting: Sendable {
    func resetAllData() async throws
}

public typealias TypistStore = PersistenceWriting & StatsQuerying & StatsResetting
