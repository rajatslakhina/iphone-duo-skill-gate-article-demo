import Foundation

/// What an agent claims after running a vendor skill: a findings list,
/// produced before it is allowed to edit anything.
public struct SkillReport: Sendable {
    public struct Item: Hashable, Codable, Sendable {
        public enum Kind: String, Codable, Sendable {
            /// One of the text patterns the scanner also knows.
            case pattern
            /// Something only judgment can see, such as size read once at launch.
            case semantic
        }

        public let path: String
        public let line: Int
        public let kind: Kind
        public let pattern: LegacyPattern?
        public let note: String

        public init(path: String, line: Int, kind: Kind, pattern: LegacyPattern?, note: String) {
            self.path = path
            self.line = line
            self.kind = kind
            self.pattern = pattern
            self.note = note
        }

        var finding: Finding? {
            guard kind == .pattern, let pattern else { return nil }
            return Finding(path: path, line: line, pattern: pattern)
        }
    }

    public let skill: SkillManifest
    public let items: [Item]

    public init(skill: SkillManifest, items: [Item]) {
        self.skill = skill
        self.items = items
    }
}

/// Checks the agent's findings list the way you'd check an API response:
/// every item has to point at a real file and a real line, and a pattern item
/// has to point at a line that actually contains the pattern.
public enum FindingsContract {
    public enum Violation: Hashable, Sendable, CustomStringConvertible {
        case unknownFile(String)
        case lineOutOfRange(path: String, line: Int, lineCount: Int)
        case patternNotOnLine(path: String, line: Int, pattern: LegacyPattern)
        case patternItemWithoutPattern(path: String, line: Int)

        public var description: String {
            switch self {
            case let .unknownFile(path): return "\(path) is not in the repo"
            case let .lineOutOfRange(path, line, count): return "\(path):\(line) does not exist (file has \(count) lines)"
            case let .patternNotOnLine(path, line, pattern): return "\(path):\(line) has no \(pattern.rawValue)"
            case let .patternItemWithoutPattern(path, line): return "\(path):\(line) is a pattern item with no pattern"
            }
        }
    }

    /// Returns one entry per item. `nil` means the item is well-formed.
    public static func validate(_ report: SkillReport, against files: [SourceFile]) -> [(item: SkillReport.Item, violation: Violation?)] {
        let byPath = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        return report.items.map { item in (item, violation(for: item, in: byPath)) }
    }

    static func violation(for item: SkillReport.Item, in files: [String: SourceFile]) -> Violation? {
        guard let file = files[item.path] else { return .unknownFile(item.path) }
        let lines = file.lines
        guard item.line >= 1, item.line <= lines.count else {
            return .lineOutOfRange(path: item.path, line: item.line, lineCount: lines.count)
        }
        guard item.kind == .pattern else { return nil }
        guard let pattern = item.pattern else {
            return .patternItemWithoutPattern(path: item.path, line: item.line)
        }
        let code = PatternScanner.stripLineComment(lines[item.line - 1])
        return pattern.matches(code) ? nil : .patternNotOnLine(path: item.path, line: item.line, pattern: pattern)
    }
}

/// The scanner's findings and the skill's findings, side by side.
public struct Reconciliation: Sendable {
    /// Found by both the skill and the scanner.
    public let confirmed: [Finding]
    /// Found by the scanner, missed by the skill, and not a known exception.
    public let missedBySkill: [Finding]
    /// Valid items the scanner cannot see. A person reads each one.
    public let needsHumanReview: [SkillReport.Item]
    /// Items that failed the findings contract. Never acted on.
    public let rejected: [(item: SkillReport.Item, violation: FindingsContract.Violation)]
    /// Scanner findings the team has already decided to keep.
    public let excepted: [Finding]

    public init(scanner: [Finding], report: SkillReport, files: [SourceFile], exceptions: [KnownException]) {
        let checked = FindingsContract.validate(report, against: files)
        var rejected: [(SkillReport.Item, FindingsContract.Violation)] = []
        var skillFindings: Set<Finding> = []
        var review: [SkillReport.Item] = []

        for (item, violation) in checked {
            if let violation {
                rejected.append((item, violation))
            } else if let finding = item.finding {
                skillFindings.insert(finding)
            } else {
                review.append(item)
            }
        }

        let isExcepted: (Finding) -> Bool = { finding in exceptions.contains { $0.covers(finding) } }
        self.excepted = scanner.filter(isExcepted)
        let open = scanner.filter { !isExcepted($0) }
        self.confirmed = open.filter { skillFindings.contains($0) }
        self.missedBySkill = open.filter { !skillFindings.contains($0) }
        self.needsHumanReview = review
        self.rejected = rejected.map { (item: $0.0, violation: $0.1) }
    }

    /// Open scanner findings: everything except known exceptions.
    public var openCount: Int { confirmed.count + missedBySkill.count }

    public var missedMustFix: [Finding] {
        missedBySkill.filter { $0.pattern.severity == .mustFix }
    }
}
