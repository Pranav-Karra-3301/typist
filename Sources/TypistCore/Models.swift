import Foundation

public enum DeviceClass: String, Codable, CaseIterable, Sendable {
    case builtIn = "built_in"
    case external
    case unknown
}

public enum TimeBucketGranularity: Sendable {
    case hour
    case day
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
        case .h1, .h12, .h24:
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
        case .hour:
            return startOfHour(for: date, calendar: calendar)
        case .day:
            return startOfDay(for: date, calendar: calendar)
        }
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
        case .hour:
            return calendar.date(byAdding: .hour, value: 1, to: date) ?? date
        case .day:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
    }
}

public struct KeyEvent: Sendable, Hashable {
    public let timestamp: Date
    public let keyCode: Int
    public let isSeparator: Bool
    public let deviceClass: DeviceClass

    public init(timestamp: Date, keyCode: Int, isSeparator: Bool, deviceClass: DeviceClass) {
        self.timestamp = timestamp
        self.keyCode = keyCode
        self.isSeparator = isSeparator
        self.deviceClass = deviceClass
    }
}

public struct WordIncrement: Sendable, Hashable {
    public let timestamp: Date
    public let deviceClass: DeviceClass

    public init(timestamp: Date, deviceClass: DeviceClass) {
        self.timestamp = timestamp
        self.deviceClass = deviceClass
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
    public var deviceBreakdown: DeviceBreakdown
    public var keyDistribution: [TopKeyStat]
    public var topKeys: [TopKeyStat]
    public var trendSeries: [TrendPoint]

    public init(
        timeframe: Timeframe,
        totalKeystrokes: Int,
        totalWords: Int,
        deviceBreakdown: DeviceBreakdown,
        keyDistribution: [TopKeyStat],
        topKeys: [TopKeyStat],
        trendSeries: [TrendPoint]
    ) {
        self.timeframe = timeframe
        self.totalKeystrokes = totalKeystrokes
        self.totalWords = totalWords
        self.deviceBreakdown = deviceBreakdown
        self.keyDistribution = keyDistribution
        self.topKeys = topKeys
        self.trendSeries = trendSeries
    }

    public static func empty(timeframe: Timeframe) -> StatsSnapshot {
        StatsSnapshot(
            timeframe: timeframe,
            totalKeystrokes: 0,
            totalWords: 0,
            deviceBreakdown: DeviceBreakdown(builtIn: 0, external: 0, unknown: 0),
            keyDistribution: [],
            topKeys: [],
            trendSeries: []
        )
    }
}

public protocol KeyboardCaptureProviding {
    var events: AsyncStream<KeyEvent> { get }
    func start() throws
    func stop()
}

public protocol PersistenceWriting: Sendable {
    func flush(events: [KeyEvent], wordIncrements: [WordIncrement]) async throws
}

public protocol StatsQuerying: Sendable {
    func snapshot(for timeframe: Timeframe, now: Date) async throws -> StatsSnapshot
}

public protocol StatsResetting: Sendable {
    func resetAllData() async throws
}

public typealias TypistStore = PersistenceWriting & StatsQuerying & StatsResetting
