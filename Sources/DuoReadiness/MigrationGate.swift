import Foundation

/// How much the agent may do with this migration right now.
public enum AgentMode: String, Sendable {
    /// Agent may apply its fixes without a person approving each one.
    case unattended
    /// Agent proposes edits from its findings list; a person applies or approves.
    case findingsOnly
    /// The skill itself is in question. Nobody runs it until it is re-pinned.
    case blocked

    public var label: String {
        switch self {
        case .unattended: return "Unattended"
        case .findingsOnly: return "Findings only"
        case .blocked: return "Blocked"
        }
    }
}

/// The lead's sign-off for a vendor-skill migration, as code.
public struct MigrationGate: Sendable {
    public enum Reason: Hashable, Sendable, CustomStringConvertible {
        case skillMissed(Finding)
        case rejectedItems(Int)
        case humanReviewPending(Int)
        case reviewPatternsOpen(Int)
        case poseMatrixFails(Int)
        case pin(String)

        public var description: String {
            switch self {
            case let .skillMissed(f): return "Skill missed \(f.pattern.rawValue) at \(f.path):\(f.line)"
            case let .rejectedItems(n): return "\(n) findings failed the contract"
            case let .humanReviewPending(n): return "\(n) semantic findings need a person"
            case let .reviewPatternsOpen(n): return "\(n) review patterns still open"
            case let .poseMatrixFails(n): return "Pose matrix fails \(n) of 4 size-class combinations"
            case let .pin(text): return text
            }
        }
    }

    public let mode: AgentMode
    public let shipReady: Bool
    public let reasons: [Reason]

    /// - Parameters:
    ///   - reconciliation: skill findings versus scanner findings.
    ///   - pin: pinned skill versus today's export.
    ///   - matrix: the root-layout policy across all size classes.
    public init(reconciliation: Reconciliation, pin: PinCheck, matrix: PoseMatrix) {
        var reasons: [Reason] = []

        switch pin {
        case .unchanged, .versionOnly: break
        case .upgraded, .changedWithoutVersionBump: reasons.append(.pin(pin.summary))
        }
        reasons += reconciliation.missedMustFix.map(Reason.skillMissed)
        if !reconciliation.rejected.isEmpty { reasons.append(.rejectedItems(reconciliation.rejected.count)) }
        if !reconciliation.needsHumanReview.isEmpty { reasons.append(.humanReviewPending(reconciliation.needsHumanReview.count)) }
        let openReview = (reconciliation.confirmed + reconciliation.missedBySkill).filter { $0.pattern.severity == .review }
        if !openReview.isEmpty { reasons.append(.reviewPatternsOpen(openReview.count)) }
        if !matrix.passes { reasons.append(.poseMatrixFails(matrix.failures.count)) }
        self.reasons = reasons

        // Mode: a skill whose content moved without a version bump is not
        // trusted at all. An upgrade is trusted only after someone re-pins it.
        // Otherwise the agent may act alone only when its list was complete,
        // valid and fully mechanical.
        switch pin {
        case .changedWithoutVersionBump, .upgraded:
            self.mode = .blocked
        case .unchanged, .versionOnly:
            let complete = reconciliation.missedBySkill.isEmpty
            let clean = reconciliation.rejected.isEmpty && reconciliation.needsHumanReview.isEmpty
            self.mode = complete && clean ? .unattended : .findingsOnly
        }

        // Ship-ready is about the code, not the agent: nothing open outside
        // the known exceptions and the matrix passes.
        self.shipReady = reconciliation.openCount == 0 && matrix.passes
    }
}

/// The brief you hand any coding agent before a platform migration.
/// The skill alone is not a brief: it does not know your exceptions or what
/// "done" means on your team.
public struct MigrationBrief: Sendable {
    public let skill: SkillManifest
    public let exceptions: [KnownException]

    public init(skill: SkillManifest, exceptions: [KnownException]) {
        self.skill = skill
        self.exceptions = exceptions
    }

    public var text: String {
        var lines: [String] = []
        lines.append("Run the \(skill.name) skill, version \(skill.version) (rules digest \(skill.digest)). If your copy differs, stop and say so.")
        lines.append("")
        lines.append("Known exceptions. Report them, do not change them:")
        if exceptions.isEmpty {
            lines.append("- none")
        } else {
            for e in exceptions { lines.append("- \(e.path): \(e.pattern.rawValue). \(e.reason)") }
        }
        lines.append("")
        lines.append("Definition of done:")
        lines.append("- the repo scan reports no open findings outside the exceptions above")
        lines.append("- the root layout passes all four size-class combinations, with no idiom check")
        lines.append("")
        lines.append("First return a findings list only, as JSON: path, line, kind (pattern or semantic), pattern, note.")
        lines.append("Every line you cite must exist and contain the pattern. Make no edits until the list is approved.")
        return lines.joined(separator: "\n")
    }
}
