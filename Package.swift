// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DuoReadiness",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DuoReadiness", targets: ["DuoReadiness"])
    ],
    targets: [
        .target(name: "DuoReadiness"),
        .testTarget(name: "DuoReadinessTests", dependencies: ["DuoReadiness"])
    ]
)
