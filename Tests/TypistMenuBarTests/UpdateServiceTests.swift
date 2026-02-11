import Foundation
import XCTest
@testable import TypistMenuBar

final class UpdateServiceTests: XCTestCase {
    func testUpdateAvailableWhenLatestBetaGreaterThanCurrent() async {
        let payload = """
        [
          {
            "tag_name": "v0.1.0-beta.3",
            "prerelease": true,
            "draft": false,
            "html_url": "https://github.com/acme/typist/releases/tag/v0.1.0-beta.3",
            "body": "beta notes",
            "published_at": "2026-02-10T12:00:00Z"
          },
          {
            "tag_name": "v0.1.0-beta.2",
            "prerelease": true,
            "draft": false,
            "html_url": "https://github.com/acme/typist/releases/tag/v0.1.0-beta.2",
            "body": "older notes",
            "published_at": "2026-02-09T12:00:00Z"
          }
        ]
        """

        let fetcher = MockFetcher(statusCode: 200, body: Data(payload.utf8))
        let service = UpdateService(
            repository: "acme/typist",
            session: fetcher,
            currentVersionProvider: { AppVersion.parse("0.1.0-beta.2") },
            now: { Date(timeIntervalSince1970: 1_739_188_000) }
        )

        let result = await service.checkForUpdates(channel: .beta)

        switch result {
        case let .updateAvailable(current, latest, _):
            XCTAssertEqual(current.description, "0.1.0-beta.2")
            XCTAssertEqual(latest.version.description, "0.1.0-beta.3")
            XCTAssertEqual(latest.tag, "v0.1.0-beta.3")
        default:
            XCTFail("Expected updateAvailable, got \(result)")
        }
    }

    func testUpToDateWhenCurrentVersionIsLatest() async {
        let payload = """
        [
          {
            "tag_name": "v0.1.0-beta.3",
            "prerelease": true,
            "draft": false,
            "html_url": "https://github.com/acme/typist/releases/tag/v0.1.0-beta.3",
            "body": "",
            "published_at": "2026-02-10T12:00:00Z"
          }
        ]
        """

        let fetcher = MockFetcher(statusCode: 200, body: Data(payload.utf8))
        let service = UpdateService(
            repository: "acme/typist",
            session: fetcher,
            currentVersionProvider: { AppVersion.parse("0.1.0-beta.3") },
            now: { Date(timeIntervalSince1970: 1_739_188_000) }
        )

        let result = await service.checkForUpdates(channel: .beta)

        switch result {
        case let .upToDate(current, _):
            XCTAssertEqual(current.description, "0.1.0-beta.3")
        default:
            XCTFail("Expected upToDate, got \(result)")
        }
    }

    func testRateLimitedWhenGitHubReturns403() async {
        let fetcher = MockFetcher(statusCode: 403, body: Data("[]".utf8))
        let service = UpdateService(
            repository: "acme/typist",
            session: fetcher,
            currentVersionProvider: { AppVersion.parse("0.1.0-beta.3") },
            now: { Date(timeIntervalSince1970: 1_739_188_000) }
        )

        let result = await service.checkForUpdates(channel: .beta)

        switch result {
        case let .unavailable(reason, _):
            XCTAssertEqual(reason, .rateLimited)
        default:
            XCTFail("Expected unavailable(.rateLimited), got \(result)")
        }
    }

    func testInvalidResponseWhenMalformedJSON() async {
        let fetcher = MockFetcher(statusCode: 200, body: Data("{oops".utf8))
        let service = UpdateService(
            repository: "acme/typist",
            session: fetcher,
            currentVersionProvider: { AppVersion.parse("0.1.0-beta.3") },
            now: { Date(timeIntervalSince1970: 1_739_188_000) }
        )

        let result = await service.checkForUpdates(channel: .beta)

        switch result {
        case let .unavailable(reason, _):
            XCTAssertEqual(reason, .invalidResponse)
        default:
            XCTFail("Expected unavailable(.invalidResponse), got \(result)")
        }
    }

    func testUpdateCheckScheduleHonorsInterval() {
        let now = Date(timeIntervalSince1970: 1_739_188_000)
        let twentyThreeHoursAgo = now.addingTimeInterval(-(23 * 3600))
        let twentyFiveHoursAgo = now.addingTimeInterval(-(25 * 3600))

        XCTAssertFalse(
            UpdateCheckSchedule.shouldRunAutoCheck(
                enabled: true,
                lastCheckedAt: twentyThreeHoursAgo,
                now: now,
                intervalHours: 24
            )
        )
        XCTAssertTrue(
            UpdateCheckSchedule.shouldRunAutoCheck(
                enabled: true,
                lastCheckedAt: twentyFiveHoursAgo,
                now: now,
                intervalHours: 24
            )
        )
        XCTAssertFalse(
            UpdateCheckSchedule.shouldRunAutoCheck(
                enabled: false,
                lastCheckedAt: nil,
                now: now,
                intervalHours: 24
            )
        )
        XCTAssertTrue(
            UpdateCheckSchedule.shouldRunAutoCheck(
                enabled: true,
                lastCheckedAt: nil,
                now: now,
                intervalHours: 24
            )
        )
    }
}

private struct MockFetcher: HTTPDataFetching {
    let statusCode: Int
    let body: Data

    func data(from url: URL) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (body, response)
    }
}
