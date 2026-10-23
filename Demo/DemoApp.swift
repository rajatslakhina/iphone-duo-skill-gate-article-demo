import SwiftUI
import DuoReadiness

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView(screen: UserDefaults.standard.string(forKey: "screen") == "matrix" ? .matrix : .gate)
        }
    }
}

enum Screen: String, CaseIterable, Identifiable {
    case gate = "Skill vs scan"
    case matrix = "Pose matrix + pin"
    var id: String { rawValue }
}

struct RootView: View {
    @State var screen: Screen

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Screen", selection: $screen) {
                        ForEach(Screen.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                switch screen {
                case .gate: GateSections()
                case .matrix: MatrixSections()
                }
                Section {
                    EmptyView()
                } footer: {
                    Text("Constructed example: a fictional app and a hand-written findings list shaped like an agent's skill run. Not output from Apple's skill.")
                }
            }
            .navigationTitle("Duo readiness")
        }
    }
}

// MARK: - Skill vs scan

struct GateSections: View {
    private let r = SampleScenario.reconciliation
    private let gate = SampleScenario.gate

    var body: some View {
        Section("Trailhead · \(SampleScenario.files.count) files · \(r.openCount) open findings") {
            HStack(spacing: 8) {
                Tile(value: r.confirmed.count, label: "List found", color: .blue)
                Tile(value: r.missedBySkill.count, label: "List missed", color: .red)
                Tile(value: r.rejected.count, label: "Invented", color: .orange)
                Tile(value: r.needsHumanReview.count, label: "Needs a person", color: .purple)
            }
            .padding(.vertical, 4)
        }
        Section("Gate") {
            HStack {
                Text("Agent mode")
                Spacer()
                Badge(text: gate.mode.label, color: gate.mode == .unattended ? .green : (gate.mode == .blocked ? .red : .orange))
            }
            HStack {
                Text("Ready to ship")
                Spacer()
                Badge(text: gate.shipReady ? "Yes" : "No", color: gate.shipReady ? .green : .red)
            }
        }
        Section("Missed by the list, caught by the scan") {
            ForEach(r.missedBySkill, id: \.self) { f in
                FindingRow(title: f.pattern.title, detail: "\(f.path):\(f.line)", color: .red)
            }
        }
        Section("Rejected by the findings contract") {
            ForEach(Array(r.rejected.enumerated()), id: \.offset) { _, entry in
                FindingRow(title: entry.violation.description, detail: entry.item.note, color: .orange)
            }
        }
        Section("Only judgment can see this") {
            ForEach(r.needsHumanReview, id: \.self) { item in
                FindingRow(title: "\(item.path):\(item.line)", detail: item.note, color: .purple)
            }
        }
    }
}

// MARK: - Pose matrix + pin

struct MatrixSections: View {
    var body: some View {
        MatrixSection(title: "Legacy root layout (idiom first)", matrix: SampleScenario.legacyMatrix)
        MatrixSection(title: "Size class only", matrix: SampleScenario.fixedMatrix)
        Section("Skill pin · app-resizability 1.0") {
            PinRow(label: "Same export", check: PinCheck.compare(pinned: SampleScenario.pinnedSkill, current: SampleScenario.pinnedSkill))
            PinRow(label: "Later export", check: PinCheck.compare(pinned: SampleScenario.pinnedSkill, current: SampleScenario.laterSkill))
            PinRow(label: "Silent change", check: PinCheck.compare(pinned: SampleScenario.pinnedSkill, current: SampleScenario.silentlyChangedSkill))
        }
    }
}

struct MatrixSection: View {
    let title: String
    let matrix: PoseMatrix

    var body: some View {
        Section {
            ForEach(matrix.cells) { cell in
                HStack {
                    Text(LayoutTraits(horizontal: cell.horizontal, vertical: cell.vertical, idiom: .phone).sizeLabel)
                        .font(.system(.subheadline, design: .monospaced))
                    Spacer()
                    Text(cell.problem ?? (cell.phone?.rawValue ?? "-"))
                        .font(.caption)
                        .foregroundStyle(cell.passes ? Color.secondary : Color.red)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: cell.passes ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(cell.passes ? Color.green : Color.red)
                }
            }
        } header: {
            Text("\(title) · \(4 - matrix.failures.count)/4 pass")
        }
    }
}

struct PinRow: View {
    let label: String
    let check: PinCheck

    private var color: Color {
        switch check {
        case .unchanged, .versionOnly: return .green
        case .upgraded: return .orange
        case .changedWithoutVersionBump: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline.weight(.medium))
            Text(check.summary).font(.caption).foregroundStyle(color)
        }
    }
}

// MARK: - Shared

struct Tile: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct FindingRow: View {
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
