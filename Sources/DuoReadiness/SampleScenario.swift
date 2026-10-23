import Foundation

/// A constructed sample: seven files from a fictional hiking app, Trailhead,
/// and a hand-written findings list shaped like what an agent returns after
/// running a resizability skill. It is not output from Apple's skill.
public enum SampleScenario {
    public static let files: [SourceFile] = [
        SourceFile(path: "App/SceneDelegate.swift", contents: """
        import UIKit

        final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
            var window: UIWindow?

            func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
                guard scene is UIWindowScene else { return }
                let window = UIWindow(frame: UIScreen.main.bounds)
                window.rootViewController = RootSplitController()
                window.makeKeyAndVisible()
                self.window = window
            }
        }
        """),
        SourceFile(path: "Feed/FeedViewController.swift", contents: """
        import UIKit

        final class FeedViewController: UICollectionViewController {
            private var columnWidth: CGFloat = 0

            override func viewIsAppearing(_ animated: Bool) {
                super.viewIsAppearing(animated)
                columnWidth = view.bounds.width / 2
            }

            func makeLayout() -> UICollectionViewLayout {
                let width = UIScreen.main.bounds.width
                let columns = UIDevice.current.userInterfaceIdiom == .pad ? 3 : 1
                return TrailGridLayout(width: width, columns: columns)
            }
        }
        """),
        SourceFile(path: "Map/MapContainerView.swift", contents: """
        import UIKit

        final class MapContainerView: UIView {
            let legend = LegendView()

            override func layoutSubviews() {
                super.layoutSubviews()
                if UIDevice.current.orientation.isLandscape {
                    legend.frame = CGRect(x: bounds.maxX - 220, y: 16, width: 200, height: bounds.height - 32)
                } else if window?.windowScene?.interfaceOrientation.isPortrait == true {
                    legend.frame = CGRect(x: 16, y: bounds.maxY - 140, width: bounds.width - 32, height: 120)
                }
            }
        }
        """),
        SourceFile(path: "Trail/HeroHeaderView.swift", contents: """
        import UIKit

        final class HeroHeaderView: UIView {
            let imageView = UIImageView()

            override init(frame: CGRect) {
                super.init(frame: frame)
                imageView.contentMode = .scaleAspectFill
                addSubview(imageView)
            }

            required init?(coder: NSCoder) { nil }

            override func layoutSubviews() {
                super.layoutSubviews()
                // iPhone 15/16 get a taller hero
                let heroHeight: CGFloat = window?.bounds.height == 844 ? 320 : 260
                imageView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: heroHeight)
            }
        }
        """),
        SourceFile(path: "App/RootSplitController.swift", contents: """
        import UIKit

        final class RootSplitController: UISplitViewController {
            override func traitCollectionDidChange(_ previous: UITraitCollection?) {
                super.traitCollectionDidChange(previous)
                // TODO: stop using UIScreen.main once the sidebar is fixed
                if traitCollection.horizontalSizeClass == .regular {
                    showIPadSidebar()
                } else {
                    showPhoneTabs()
                }
            }
        }
        """),
        SourceFile(path: "Legacy/LegacyBridge+Layout.swift", contents: """
        import UIKit

        extension LegacyBridge {
            /// Kept from the Objective-C era. Still called by the trip planner.
            func plannerIsLandscape() -> Bool {
                let orientation = UIApplication.shared.statusBarOrientation
                return orientation == .landscapeLeft || orientation == .landscapeRight
            }
        }
        """),
        SourceFile(path: "Debug/DebugOverlay.swift", contents: """
        import UIKit

        #if DEBUG
        final class DebugOverlay: UILabel {
            func refresh() {
                text = "native scale \\(UIScreen.main.nativeScale)"
            }
        }
        #endif
        """)
    ]

    public static let exceptions: [KnownException] = [
        KnownException(
            path: "Debug/DebugOverlay.swift",
            pattern: .mainScreen,
            reason: "Debug builds only. Shows the physical screen on purpose."
        )
    ]

    static let resizabilityRules = [
        "Replace UIScreen.main sizing with view or window bounds",
        "Re-read size on every change, not once at launch",
        "Read scale from the trait collection",
        "Create windows from a scene",
        "Remove layout decisions based on orientation",
        "Choose layout by size class, not idiom",
        "Do not treat regular width as iPad",
        "Remove checks for specific device sizes"
    ]

    /// The version the team pinned and reviewed.
    public static let pinnedSkill = SkillManifest(
        name: "app-resizability",
        version: "1.0",
        rules: resizabilityRules
    )

    /// A constructed later export with one rule added and the version moved.
    public static let laterSkill = SkillManifest(
        name: "app-resizability",
        version: "1.1",
        rules: resizabilityRules + ["Choose fill or fit for full-bleed media by aspect ratio"]
    )

    /// A constructed export whose rules changed while the version stayed put.
    public static let silentlyChangedSkill = SkillManifest(
        name: "app-resizability",
        version: "1.0",
        rules: Array(resizabilityRules.dropLast()) + ["Remove checks for specific device widths"]
    )

    /// Hand-written. Seven correct pattern items, one useful semantic item the
    /// scanner cannot see, and one item citing a line that does not exist.
    public static let skillReport = SkillReport(skill: pinnedSkill, items: [
        .init(path: "App/SceneDelegate.swift", line: 8, kind: .pattern, pattern: .mainScreen,
              note: "Use UIWindow(windowScene:)"),
        .init(path: "Feed/FeedViewController.swift", line: 12, kind: .pattern, pattern: .mainScreen,
              note: "Size the grid from the collection view's bounds"),
        .init(path: "Feed/FeedViewController.swift", line: 13, kind: .pattern, pattern: .idiomCheck,
              note: "Pick columns from available width"),
        .init(path: "Feed/FeedViewController.swift", line: 8, kind: .semantic, pattern: nil,
              note: "Column width is read once in viewIsAppearing; a fold mid-session leaves it stale"),
        .init(path: "Map/MapContainerView.swift", line: 8, kind: .pattern, pattern: .deviceOrientation,
              note: "Compare bounds width and height instead"),
        .init(path: "Map/MapContainerView.swift", line: 10, kind: .pattern, pattern: .interfaceOrientation,
              note: "Compare bounds width and height instead"),
        .init(path: "Trail/HeroHeaderView.swift", line: 8, kind: .pattern, pattern: .fullBleedFill,
              note: "Choose fill or fit by aspect ratio"),
        .init(path: "App/RootSplitController.swift", line: 7, kind: .pattern, pattern: .regularWidthMeansIPad,
              note: "Sidebar now appears on iPhone Duo too; confirm it works there"),
        .init(path: "Map/MapContainerView.swift", line: 31, kind: .pattern, pattern: .mainScreen,
              note: "Legend sizing reads the main screen")
    ])

    public static var scannerFindings: [Finding] { PatternScanner.scan(files) }

    public static var reconciliation: Reconciliation {
        Reconciliation(scanner: scannerFindings, report: skillReport, files: files, exceptions: exceptions)
    }

    public static var legacyMatrix: PoseMatrix { PoseMatrix(policy: SampleLayoutPolicies.legacy) }
    public static var fixedMatrix: PoseMatrix { PoseMatrix(policy: SampleLayoutPolicies.sizeClassOnly) }

    public static var gate: MigrationGate {
        MigrationGate(
            reconciliation: reconciliation,
            pin: PinCheck.compare(pinned: pinnedSkill, current: pinnedSkill),
            matrix: legacyMatrix
        )
    }

    public static var brief: MigrationBrief { MigrationBrief(skill: pinnedSkill, exceptions: exceptions) }
}
