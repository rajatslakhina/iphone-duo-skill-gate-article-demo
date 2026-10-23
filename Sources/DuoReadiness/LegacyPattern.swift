import Foundation

/// The layout assumptions Apple's iPhone Duo guidance tells you to remove.
/// Each case maps to one bullet in "Step 2: Fix patterns" on
/// developer.apple.com/iphone-duo/prepare.
public enum LegacyPattern: String, CaseIterable, Codable, Sendable {
    case mainScreen
    case deviceOrientation
    case statusBarOrientation
    case interfaceOrientation
    case idiomCheck
    case fixedDeviceSize
    case regularWidthMeansIPad
    case fullBleedFill

    /// Must-fix patterns block the gate. Review patterns are legitimate in
    /// some code paths, so a person decides.
    public enum Severity: String, Codable, Sendable {
        case mustFix
        case review
    }

    public var severity: Severity {
        switch self {
        case .regularWidthMeansIPad, .fullBleedFill: return .review
        default: return .mustFix
        }
    }

    public var title: String {
        switch self {
        case .mainScreen: return "Sizes from UIScreen.main"
        case .deviceOrientation: return "Layout from device orientation"
        case .statusBarOrientation: return "Layout from status bar orientation"
        case .interfaceOrientation: return "Layout from interface orientation"
        case .idiomCheck: return "Layout chosen by idiom"
        case .fixedDeviceSize: return "Checks a specific device size"
        case .regularWidthMeansIPad: return "Regular width treated as iPad"
        case .fullBleedFill: return "Full-bleed fill may crop"
        }
    }

    /// True when `line` (already stripped of comments) contains this pattern.
    func matches(_ line: String) -> Bool {
        switch self {
        case .mainScreen:
            return line.contains("UIScreen.main")
        case .deviceOrientation:
            return line.contains("UIDevice.current.orientation")
        case .statusBarOrientation:
            return line.contains("statusBarOrientation")
        case .interfaceOrientation:
            return line.contains("interfaceOrientation")
        case .idiomCheck:
            return line.contains("userInterfaceIdiom == .pad") || line.contains("userInterfaceIdiom == .phone")
        case .fixedDeviceSize:
            return Self.comparesDimensionToLiteral(line)
        case .regularWidthMeansIPad:
            return line.contains("horizontalSizeClass == .regular")
        case .fullBleedFill:
            return line.contains(".scaleAspectFill") || line.contains("contentMode: .fill")
        }
    }

    /// Matches `.height == 844`, `.width == 390` and similar: a width or height
    /// compared for equality with a three- or four-digit literal.
    static func comparesDimensionToLiteral(_ line: String) -> Bool {
        for key in [".height ==", ".width =="] {
            var searchStart = line.startIndex
            while let range = line.range(of: key, range: searchStart..<line.endIndex) {
                let digits = line[range.upperBound...]
                    .drop { $0 == " " }
                    .prefix { $0.isNumber }
                if (3...4).contains(digits.count) { return true }
                searchStart = range.upperBound
            }
        }
        return false
    }
}

/// One Swift file in the repository being migrated.
public struct SourceFile: Hashable, Sendable {
    public let path: String
    public let contents: String

    public init(path: String, contents: String) {
        self.path = path
        self.contents = contents
    }

    public var lines: [String] {
        contents.components(separatedBy: "\n")
    }
}

/// A pattern found at a file and line. Lines are 1-based.
public struct Finding: Hashable, Codable, Sendable, Comparable {
    public let path: String
    public let line: Int
    public let pattern: LegacyPattern

    public init(path: String, line: Int, pattern: LegacyPattern) {
        self.path = path
        self.line = line
        self.pattern = pattern
    }

    public static func < (lhs: Finding, rhs: Finding) -> Bool {
        (lhs.path, lhs.line, lhs.pattern.rawValue) < (rhs.path, rhs.line, rhs.pattern.rawValue)
    }
}

/// A finding the team has decided to keep, with the reason written down.
public struct KnownException: Hashable, Sendable {
    public let path: String
    public let pattern: LegacyPattern
    public let reason: String

    public init(path: String, pattern: LegacyPattern, reason: String) {
        self.path = path
        self.pattern = pattern
        self.reason = reason
    }

    func covers(_ finding: Finding) -> Bool {
        finding.path == path && finding.pattern == pattern
    }
}

/// The deterministic half of the migration: a plain text scan that never
/// gets tired and never skips a file. It cannot judge intent, which is why
/// `review` patterns exist.
public enum PatternScanner {
    public static func scan(_ files: [SourceFile]) -> [Finding] {
        var findings: [Finding] = []
        for file in files {
            for (index, rawLine) in file.lines.enumerated() {
                let code = stripLineComment(rawLine)
                guard !code.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                for pattern in LegacyPattern.allCases where pattern.matches(code) {
                    findings.append(Finding(path: file.path, line: index + 1, pattern: pattern))
                }
            }
        }
        return findings.sorted()
    }

    /// Drops everything after `//`. Good enough for a migration scan; it does
    /// not try to parse string literals that contain `//`.
    static func stripLineComment(_ line: String) -> String {
        guard let range = line.range(of: "//") else { return line }
        return String(line[..<range.lowerBound])
    }
}
