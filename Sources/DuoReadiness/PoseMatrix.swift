import Foundation

public enum SizeClass: String, CaseIterable, Sendable {
    case compact
    case regular
}

public enum Idiom: String, CaseIterable, Sendable {
    case phone
    case pad
}

public struct LayoutTraits: Hashable, Sendable {
    public let horizontal: SizeClass
    public let vertical: SizeClass
    public let idiom: Idiom

    public init(horizontal: SizeClass, vertical: SizeClass, idiom: Idiom) {
        self.horizontal = horizontal
        self.vertical = vertical
        self.idiom = idiom
    }

    public var sizeLabel: String {
        "\(horizontal == .compact ? "C" : "R")w · \(vertical == .compact ? "C" : "R")h"
    }
}

public enum RootLayout: String, Sendable {
    case tabs
    case sidebar
    case splitWithInspector
}

/// iPhone Duo means an iPhone app can get any combination of size classes.
/// The matrix checks two properties of a root-layout decision across all four
/// combinations: it always returns a layout, and the layout depends on size
/// class only, never on idiom.
public struct PoseMatrix: Sendable {
    public struct Cell: Sendable, Identifiable {
        public let horizontal: SizeClass
        public let vertical: SizeClass
        public let phone: RootLayout?
        public let pad: RootLayout?

        public var id: String { "\(horizontal.rawValue)-\(vertical.rawValue)" }

        public var problem: String? {
            if phone == nil { return "No layout on iPhone" }
            if pad == nil { return "No layout on iPad" }
            if phone != pad { return "iPhone gets \(phone?.rawValue ?? "-"), iPad gets \(pad?.rawValue ?? "-")" }
            return nil
        }

        public var passes: Bool { problem == nil }
    }

    public let cells: [Cell]

    public init(policy: (LayoutTraits) -> RootLayout?) {
        var cells: [Cell] = []
        for horizontal in SizeClass.allCases {
            for vertical in SizeClass.allCases {
                cells.append(Cell(
                    horizontal: horizontal,
                    vertical: vertical,
                    phone: policy(LayoutTraits(horizontal: horizontal, vertical: vertical, idiom: .phone)),
                    pad: policy(LayoutTraits(horizontal: horizontal, vertical: vertical, idiom: .pad))
                ))
            }
        }
        self.cells = cells
    }

    public var failures: [Cell] { cells.filter { !$0.passes } }
    public var passes: Bool { failures.isEmpty }
}

/// Two root-layout policies for the sample app.
public enum SampleLayoutPolicies {
    /// The pre-Duo habit: iPad gets the sidebar, iPhone is assumed compact
    /// width, so an iPhone with regular width falls through to nothing.
    public static func legacy(_ traits: LayoutTraits) -> RootLayout? {
        switch (traits.idiom, traits.horizontal) {
        case (.pad, _): return .sidebar
        case (.phone, .compact): return .tabs
        case (.phone, .regular): return nil
        }
    }

    /// Size class only. Regular width and regular height earns the inspector.
    public static func sizeClassOnly(_ traits: LayoutTraits) -> RootLayout? {
        switch (traits.horizontal, traits.vertical) {
        case (.compact, _): return .tabs
        case (.regular, .compact): return .sidebar
        case (.regular, .regular): return .splitWithInspector
        }
    }
}
