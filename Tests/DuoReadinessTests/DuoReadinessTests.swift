import XCTest
@testable import DuoReadiness

final class PatternScannerTests: XCTestCase {
    func testSampleRepoHasTenFindingsAcrossSevenFiles() {
        let findings = SampleScenario.scannerFindings
        XCTAssertEqual(SampleScenario.files.count, 7)
        XCTAssertEqual(findings.count, 10)
        XCTAssertEqual(Set(findings.map(\.pattern)), Set(LegacyPattern.allCases))
    }

    func testCommentedOutPatternIsIgnored() {
        let file = SourceFile(path: "A.swift", contents: "// TODO: stop using UIScreen.main\nlet x = 1 // UIScreen.main later")
        XCTAssertTrue(PatternScanner.scan([file]).isEmpty)
    }

    func testFixedDeviceSizeNeedsThreeOrFourDigits() {
        XCTAssertTrue(LegacyPattern.comparesDimensionToLiteral("if bounds.height == 844 {"))
        XCTAssertTrue(LegacyPattern.comparesDimensionToLiteral("w.width ==390"))
        XCTAssertFalse(LegacyPattern.comparesDimensionToLiteral("if bounds.height == 0 {"))
        XCTAssertFalse(LegacyPattern.comparesDimensionToLiteral("if bounds.height == other.height {"))
        XCTAssertFalse(LegacyPattern.comparesDimensionToLiteral("if a.width == 12345 {"))
    }

    func testStatusBarOrientationIsNotDoubleCountedAsInterfaceOrientation() {
        let file = SourceFile(path: "A.swift", contents: "let o = UIApplication.shared.statusBarOrientation")
        XCTAssertEqual(PatternScanner.scan([file]).map(\.pattern), [.statusBarOrientation])
    }

    func testEmptyRepoScansClean() {
        XCTAssertTrue(PatternScanner.scan([]).isEmpty)
        XCTAssertTrue(PatternScanner.scan([SourceFile(path: "E.swift", contents: "")]).isEmpty)
    }
}

final class ReconciliationTests: XCTestCase {
    func testSkillFindsSevenOfNineOpenFindings() {
        let r = SampleScenario.reconciliation
        XCTAssertEqual(r.excepted.count, 1)
        XCTAssertEqual(r.openCount, 9)
        XCTAssertEqual(r.confirmed.count, 7)
        XCTAssertEqual(r.missedBySkill, [
            Finding(path: "Legacy/LegacyBridge+Layout.swift", line: 6, pattern: .statusBarOrientation),
            Finding(path: "Trail/HeroHeaderView.swift", line: 17, pattern: .fixedDeviceSize)
        ])
        XCTAssertEqual(r.missedMustFix.count, 2)
    }

    func testSemanticItemGoesToHumanReview() {
        let r = SampleScenario.reconciliation
        XCTAssertEqual(r.needsHumanReview.count, 1)
        XCTAssertEqual(r.needsHumanReview.first?.path, "Feed/FeedViewController.swift")
        XCTAssertEqual(r.needsHumanReview.first?.line, 8)
    }

    func testInventedLineIsRejectedByContract() {
        let r = SampleScenario.reconciliation
        XCTAssertEqual(r.rejected.count, 1)
        XCTAssertEqual(r.rejected.first?.violation, .lineOutOfRange(path: "Map/MapContainerView.swift", line: 31, lineCount: 14))
    }

    func testContractRejectsWrongPatternUnknownFileAndMissingPattern() {
        let files = SampleScenario.files
        let report = SkillReport(skill: SampleScenario.pinnedSkill, items: [
            .init(path: "App/SceneDelegate.swift", line: 9, kind: .pattern, pattern: .mainScreen, note: ""),
            .init(path: "Nope.swift", line: 1, kind: .pattern, pattern: .mainScreen, note: ""),
            .init(path: "App/SceneDelegate.swift", line: 8, kind: .pattern, pattern: nil, note: ""),
            .init(path: "App/SceneDelegate.swift", line: 0, kind: .semantic, pattern: nil, note: "")
        ])
        let violations = FindingsContract.validate(report, against: files).map(\.violation)
        XCTAssertEqual(violations, [
            .patternNotOnLine(path: "App/SceneDelegate.swift", line: 9, pattern: .mainScreen),
            .unknownFile("Nope.swift"),
            .patternItemWithoutPattern(path: "App/SceneDelegate.swift", line: 8),
            .lineOutOfRange(path: "App/SceneDelegate.swift", line: 0, lineCount: 13)
        ])
    }
}

final class PoseMatrixTests: XCTestCase {
    func testLegacyPolicyFailsAllFourCombinations() {
        let m = SampleScenario.legacyMatrix
        XCTAssertEqual(m.cells.count, 4)
        XCTAssertEqual(m.failures.count, 4)
        let regularRegular = m.cells.first { $0.horizontal == .regular && $0.vertical == .regular }
        XCTAssertEqual(regularRegular?.problem, "No layout on iPhone")
        let compactRegular = m.cells.first { $0.horizontal == .compact && $0.vertical == .regular }
        XCTAssertEqual(compactRegular?.problem, "iPhone gets tabs, iPad gets sidebar")
    }

    func testSizeClassOnlyPolicyPasses() {
        XCTAssertTrue(SampleScenario.fixedMatrix.passes)
    }
}

final class PinCheckTests: XCTestCase {
    func testUnchanged() {
        XCTAssertEqual(PinCheck.compare(pinned: SampleScenario.pinnedSkill, current: SampleScenario.pinnedSkill), .unchanged)
    }

    func testUpgradeReportsAddedRule() {
        let check = PinCheck.compare(pinned: SampleScenario.pinnedSkill, current: SampleScenario.laterSkill)
        XCTAssertEqual(check, .upgraded(from: "1.0", to: "1.1",
                                        added: ["Choose fill or fit for full-bleed media by aspect ratio"], removed: []))
    }

    func testSilentContentChangeIsCaughtByDigest() {
        let check = PinCheck.compare(pinned: SampleScenario.pinnedSkill, current: SampleScenario.silentlyChangedSkill)
        XCTAssertEqual(check, .changedWithoutVersionBump(added: ["Remove checks for specific device widths"],
                                                          removed: ["Remove checks for specific device sizes"]))
        XCTAssertNotEqual(SampleScenario.pinnedSkill.digest, SampleScenario.silentlyChangedSkill.digest)
        XCTAssertEqual(SampleScenario.pinnedSkill.digest.count, 16)
    }

    func testVersionOnlyBump() {
        let bumped = SkillManifest(name: "app-resizability", version: "1.0.1", rules: SampleScenario.pinnedSkill.rules)
        XCTAssertEqual(PinCheck.compare(pinned: SampleScenario.pinnedSkill, current: bumped), .versionOnly(from: "1.0", to: "1.0.1"))
    }
}

final class MigrationGateTests: XCTestCase {
    func testSampleIsFindingsOnlyAndNotShipReady() {
        let gate = SampleScenario.gate
        XCTAssertEqual(gate.mode, .findingsOnly)
        XCTAssertFalse(gate.shipReady)
        XCTAssertEqual(gate.reasons.count, 6)
        XCTAssertTrue(gate.reasons.contains(.poseMatrixFails(4)))
        XCTAssertTrue(gate.reasons.contains(.reviewPatternsOpen(2)))
    }

    func testSilentSkillChangeBlocksTheAgent() {
        let gate = MigrationGate(
            reconciliation: SampleScenario.reconciliation,
            pin: PinCheck.compare(pinned: SampleScenario.pinnedSkill, current: SampleScenario.silentlyChangedSkill),
            matrix: SampleScenario.fixedMatrix
        )
        XCTAssertEqual(gate.mode, .blocked)
    }

    func testCompleteCleanReportEarnsUnattended() {
        let files = [SourceFile(path: "A.swift", contents: "let w = UIScreen.main.bounds.width")]
        let report = SkillReport(skill: SampleScenario.pinnedSkill, items: [
            .init(path: "A.swift", line: 1, kind: .pattern, pattern: .mainScreen, note: "")
        ])
        let r = Reconciliation(scanner: PatternScanner.scan(files), report: report, files: files, exceptions: [])
        let gate = MigrationGate(reconciliation: r, pin: .unchanged, matrix: SampleScenario.fixedMatrix)
        XCTAssertEqual(gate.mode, .unattended)
        XCTAssertFalse(gate.shipReady, "Unattended means the agent may fix it, not that it is fixed")
    }

    func testFixedRepoIsShipReady() {
        let files = [SourceFile(path: "A.swift", contents: "let w = view.bounds.width")]
        let r = Reconciliation(scanner: PatternScanner.scan(files),
                               report: SkillReport(skill: SampleScenario.pinnedSkill, items: []),
                               files: files, exceptions: [])
        let gate = MigrationGate(reconciliation: r, pin: .unchanged, matrix: SampleScenario.fixedMatrix)
        XCTAssertTrue(gate.shipReady)
        XCTAssertTrue(gate.reasons.isEmpty)
    }

    func testBriefCarriesVersionDigestExceptionsAndFindingsFirstRule() {
        let text = SampleScenario.brief.text
        XCTAssertTrue(text.contains("version 1.0"))
        XCTAssertTrue(text.contains(SampleScenario.pinnedSkill.digest))
        XCTAssertTrue(text.contains("Debug/DebugOverlay.swift"))
        XCTAssertTrue(text.contains("Make no edits until the list is approved."))
    }
}
