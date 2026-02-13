import Foundation

enum AppStorage {
    private static let legacyProductionDirectory = "Typist"
    private static let devDirectoryPrefix = "\(legacyProductionDirectory)-dev"
    private static let suitePrefix = "com.typist.typist"
    private static let fallbackDefaultsNamespace = "default"
    private static let defaultProcessNamespace = "local"

    static var defaults: UserDefaults {
        guard !isPackagedBuild else {
            return .standard
        }

        let namespace = sanitizedNamespace(for: dataNamespace)
        let normalized = namespace.isEmpty ? fallbackDefaultsNamespace : namespace
        return UserDefaults(suiteName: "\(suitePrefix).\(normalized)") ?? .standard
    }

    static func databaseURL() throws -> URL {
        let appSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let databaseDirectoryName = isPackagedBuild
            ? legacyProductionDirectory
            : "\(devDirectoryPrefix)-\(sanitizedNamespace(for: dataNamespace))"
        let appDirectory = appSupportDirectory.appendingPathComponent(databaseDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        return appDirectory.appendingPathComponent("typist.sqlite3", isDirectory: false)
    }

    private static var isPackagedBuild: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    private static var dataNamespace: String {
        if let override = ProcessInfo.processInfo.environment["TYPIST_DATA_NAMESPACE"], !override.isEmpty {
            return override
        }

        return ProcessInfo.processInfo.processName
    }

    private static func sanitizedNamespace(for value: String) -> String {
        let lowered = value.lowercased()
        let allowed = lowered.filter { character in
            character.isASCII && (character.isNumber || character.isLetter || character == "-" || character == "_")
        }

        let trimmed = allowed.trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
        return trimmed.isEmpty ? defaultProcessNamespace : trimmed
    }
}
