// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "StorageAnalysis",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (model, scanner, classifier) — no UI, unit-testable.
        .target(name: "StorageAnalysisCore"),
        // The menu-bar app. Bundled into StorageAnalysis.app by scripts/bundle.sh.
        .executableTarget(
            name: "StorageAnalysis",
            dependencies: ["StorageAnalysisCore"]
        ),
        // Unit checks for StorageAnalysisCore: `swift run CoreChecks`.
        // A plain executable because with only the Command Line Tools installed
        // (no Xcode) XCTest is missing and `swift test` silently runs no
        // swift-testing tests.
        .executableTarget(
            name: "CoreChecks",
            dependencies: ["StorageAnalysisCore"]
        ),
        // Debug tool: prints a real scan. `swift run storage-scan`
        .executableTarget(
            name: "storage-scan",
            dependencies: ["StorageAnalysisCore"]
        ),
    ]
)
