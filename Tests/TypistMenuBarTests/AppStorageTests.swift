import Foundation
import XCTest
@testable import TypistMenuBar

final class AppStorageTests: XCTestCase {
    private func withDataNamespace(_ namespace: String, block: () -> Void) {
        let key = "TYPIST_DATA_NAMESPACE"
        let previous = ProcessInfo.processInfo.environment[key]
        setenv(key, namespace, 1)
        block()
        if let previous {
            setenv(key, previous, 1)
        } else {
            unsetenv(key)
        }
    }

    func testDefaultsIsNamespacedForNonPackagedBuild() {
        let marker = "typist.storage.tests.defaults"

        withDataNamespace("local-feature-a") {
            guard let featureDefaults = UserDefaults(suiteName: "com.typist.typist.local-feature-a") else {
                XCTFail("Failed to create namespaced UserDefaults")
                return
            }
            let featureBDefaults = UserDefaults(suiteName: "com.typist.typist.local-feature-b")

            featureDefaults.removeObject(forKey: marker)
            featureBDefaults?.removeObject(forKey: marker)

            AppStorage.defaults.set("visible", forKey: marker)
            XCTAssertEqual(AppStorage.defaults.string(forKey: marker), "visible")
            XCTAssertNil(featureBDefaults?.string(forKey: marker))

            featureDefaults.removeObject(forKey: marker)
            featureBDefaults?.removeObject(forKey: marker)
        }
    }

    func testDatabasePathUsesDataNamespace() {
        let namespace = "local-feature-b"
        withDataNamespace(namespace) {
            let appSupport: URL
            do {
                appSupport = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
            } catch {
                XCTFail("Failed to resolve application support URL: \(error)")
                return
            }

            let url: URL
            do {
                url = try AppStorage.databaseURL()
            } catch {
                XCTFail("Failed to resolve database URL: \(error)")
                return
            }

            XCTAssertTrue(url.path.hasSuffix("/Typist-dev-\(namespace)/typist.sqlite3"))
            XCTAssertTrue(url.path.hasPrefix(appSupport.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
            XCTAssertNil(url.lastPathComponent.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines))

            let directory = url.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: directory)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        }
    }
}
