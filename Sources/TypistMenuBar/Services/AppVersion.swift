import Foundation

struct AppVersion: Comparable, CustomStringConvertible, Equatable, Sendable {
    struct Prerelease: Equatable, Sendable {
        let label: String
        let number: Int?
    }

    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: Prerelease?

    static func parse(_ value: String) -> AppVersion? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized: Substring
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            normalized = trimmed.dropFirst()
        } else {
            normalized = Substring(trimmed)
        }

        let pieces = normalized.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard pieces.count >= 1 else { return nil }

        let coreParts = pieces[0].split(separator: ".", omittingEmptySubsequences: false)
        guard coreParts.count == 3,
              let major = Int(coreParts[0]),
              let minor = Int(coreParts[1]),
              let patch = Int(coreParts[2]) else {
            return nil
        }

        var prerelease: Prerelease?
        if pieces.count == 2 {
            let pre = pieces[1]
            guard !pre.isEmpty else { return nil }

            let preParts = pre.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawLabel = preParts.first, !rawLabel.isEmpty else {
                return nil
            }

            let label = rawLabel.lowercased()
            var number: Int?
            if preParts.count == 2 {
                guard let parsed = Int(preParts[1]) else { return nil }
                number = parsed
            }
            prerelease = Prerelease(label: label, number: number)
        }

        return AppVersion(major: major, minor: minor, patch: patch, prerelease: prerelease)
    }

    static func current(bundle: Bundle = .main) -> AppVersion? {
        guard let raw = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }
        return parse(raw)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        case let (.some(left), .some(right)):
            if left.label != right.label {
                return left.label < right.label
            }

            switch (left.number, right.number) {
            case let (.some(a), .some(b)):
                return a < b
            case (.none, .some):
                return true
            case (.some, .none):
                return false
            case (.none, .none):
                return false
            }
        }
    }

    var description: String {
        var result = "\(major).\(minor).\(patch)"
        if let prerelease {
            result += "-\(prerelease.label)"
            if let number = prerelease.number {
                result += ".\(number)"
            }
        }
        return result
    }
}
