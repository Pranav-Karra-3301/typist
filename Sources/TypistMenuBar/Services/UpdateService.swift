import Foundation

enum UpdateChannel: Sendable, Equatable {
    case beta
    case stable
}

struct UpdateRelease: Equatable, Sendable {
    let tag: String
    let version: AppVersion
    let htmlURL: URL
    let notes: String
    let prerelease: Bool
    let publishedAt: Date?
}

enum UpdateCheckError: Error, Equatable, Sendable {
    case invalidCurrentVersion
    case invalidRequestURL
    case rateLimited
    case invalidResponse
    case unexpectedStatusCode(Int)
    case networkFailure(String)

    var userMessage: String {
        switch self {
        case .invalidCurrentVersion:
            return "Unable to determine current app version."
        case .invalidRequestURL:
            return "Update service is misconfigured."
        case .rateLimited:
            return "GitHub rate limit reached. Try again later."
        case .invalidResponse:
            return "Could not parse release information."
        case let .unexpectedStatusCode(code):
            return "Update check failed with HTTP \(code)."
        case let .networkFailure(message):
            return "Network error while checking updates: \(message)"
        }
    }
}

enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(current: AppVersion, checkedAt: Date)
    case updateAvailable(current: AppVersion, latest: UpdateRelease, checkedAt: Date)
    case unavailable(reason: UpdateCheckError, checkedAt: Date)
}

struct UpdateCheckSchedule {
    static func shouldRunAutoCheck(
        enabled: Bool,
        lastCheckedAt: Date?,
        now: Date,
        intervalHours: Double
    ) -> Bool {
        guard enabled else { return false }
        guard intervalHours > 0 else { return true }
        guard let lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= intervalHours * 3600
    }
}

protocol HTTPDataFetching: Sendable {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPDataFetching {}

protocol UpdateChecking: Sendable {
    var releasesPageURL: URL { get }
    func checkForUpdates(channel: UpdateChannel) async -> UpdateCheckResult
}

actor UpdateService: UpdateChecking {
    private struct GitHubRelease: Decodable {
        let tagName: String
        let prerelease: Bool
        let draft: Bool
        let htmlURL: URL
        let body: String?
        let publishedAt: Date?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case prerelease
            case draft
            case htmlURL = "html_url"
            case body
            case publishedAt = "published_at"
        }
    }

    let releasesPageURL: URL

    private let repository: String
    private let session: any HTTPDataFetching
    private let currentVersionProvider: @Sendable () -> AppVersion?
    private let now: @Sendable () -> Date

    init(
        repository: String,
        releasesPageURL: URL? = nil,
        session: any HTTPDataFetching = URLSession.shared,
        currentVersionProvider: @escaping @Sendable () -> AppVersion?,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        let fallback = URL(string: "https://github.com/\(repository)/releases")!
        self.releasesPageURL = releasesPageURL ?? fallback
        self.session = session
        self.currentVersionProvider = currentVersionProvider
        self.now = now
    }

    func checkForUpdates(channel: UpdateChannel) async -> UpdateCheckResult {
        let checkedAt = now()

        guard let currentVersion = currentVersionProvider() else {
            return .unavailable(reason: .invalidCurrentVersion, checkedAt: checkedAt)
        }

        guard let apiURL = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=20") else {
            return .unavailable(reason: .invalidRequestURL, checkedAt: checkedAt)
        }

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(from: apiURL)
        } catch {
            return .unavailable(reason: .networkFailure(error.localizedDescription), checkedAt: checkedAt)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .unavailable(reason: .invalidResponse, checkedAt: checkedAt)
        }

        if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
            return .unavailable(reason: .rateLimited, checkedAt: checkedAt)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            return .unavailable(reason: .unexpectedStatusCode(httpResponse.statusCode), checkedAt: checkedAt)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let releases: [GitHubRelease]
        do {
            releases = try decoder.decode([GitHubRelease].self, from: responseData)
        } catch {
            return .unavailable(reason: .invalidResponse, checkedAt: checkedAt)
        }

        let parsedReleases = releases.compactMap { release -> UpdateRelease? in
            guard !release.draft, let version = AppVersion.parse(release.tagName) else {
                return nil
            }

            if channel == .stable, release.prerelease {
                return nil
            }

            return UpdateRelease(
                tag: release.tagName,
                version: version,
                htmlURL: release.htmlURL,
                notes: release.body ?? "",
                prerelease: release.prerelease,
                publishedAt: release.publishedAt
            )
        }

        guard let latest = parsedReleases.max(by: { $0.version < $1.version }) else {
            return .unavailable(reason: .invalidResponse, checkedAt: checkedAt)
        }

        if latest.version > currentVersion {
            return .updateAvailable(current: currentVersion, latest: latest, checkedAt: checkedAt)
        }

        return .upToDate(current: currentVersion, checkedAt: checkedAt)
    }
}

extension UpdateService {
    static func makeDefault(
        bundle: Bundle = .main,
        session: any HTTPDataFetching = URLSession.shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> UpdateService {
        let repository =
            (bundle.object(forInfoDictionaryKey: "TypistUpdateRepo") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "pranavkarra/typist"

        let releasesURL =
            (bundle.object(forInfoDictionaryKey: "TypistReleasesURL") as? String)
            .flatMap { URL(string: $0) }

        let provider: @Sendable () -> AppVersion? = {
            AppVersion.current(bundle: bundle)
        }

        return UpdateService(
            repository: repository,
            releasesPageURL: releasesURL,
            session: session,
            currentVersionProvider: provider,
            now: now
        )
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
