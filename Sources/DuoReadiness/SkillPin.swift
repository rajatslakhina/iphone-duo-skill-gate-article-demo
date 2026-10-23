import Foundation

/// The parts of an exported agent skill a team pins: its name, its declared
/// version, and the rules it contains.
public struct SkillManifest: Hashable, Codable, Sendable {
    public let name: String
    public let version: String
    public let rules: [String]

    public init(name: String, version: String, rules: [String]) {
        self.name = name
        self.version = version
        self.rules = rules
    }

    /// A stable 64-bit FNV-1a digest of the rules, so two exports can be
    /// compared without trusting the version string. Not a security hash.
    public var digest: String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in rules.joined(separator: "\n").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }
}

/// Compares the skill you pinned with the skill the toolchain exports today.
public enum PinCheck: Equatable, Sendable {
    case unchanged
    /// Version moved and content moved: read the diff, then re-pin.
    case upgraded(from: String, to: String, added: [String], removed: [String])
    /// Content moved but the version string did not. Treat as untrusted.
    case changedWithoutVersionBump(added: [String], removed: [String])
    /// Version moved but the rules are identical.
    case versionOnly(from: String, to: String)

    public static func compare(pinned: SkillManifest, current: SkillManifest) -> PinCheck {
        let added = current.rules.filter { !pinned.rules.contains($0) }
        let removed = pinned.rules.filter { !current.rules.contains($0) }
        let sameContent = pinned.digest == current.digest
        let sameVersion = pinned.version == current.version
        switch (sameVersion, sameContent) {
        case (true, true): return .unchanged
        case (true, false): return .changedWithoutVersionBump(added: added, removed: removed)
        case (false, true): return .versionOnly(from: pinned.version, to: current.version)
        case (false, false): return .upgraded(from: pinned.version, to: current.version, added: added, removed: removed)
        }
    }

    public var summary: String {
        switch self {
        case .unchanged: return "Pinned skill unchanged"
        case let .upgraded(from, to, added, removed): return "Skill \(from) → \(to): +\(added.count) / −\(removed.count) rules"
        case let .changedWithoutVersionBump(added, removed): return "Rules changed with no version bump: +\(added.count) / −\(removed.count)"
        case let .versionOnly(from, to): return "Version \(from) → \(to), rules identical"
        }
    }
}
