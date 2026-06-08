// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "claude-spotlight",
    platforms: [.macOS(.v14)],
    targets: [
        // Reusable engine — will be linked by the macOS app in Phase 2.
        .target(
            name: "CSpotKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Phase-0 CLI harness: `swift run cspot "<query>"` → ranked candidate JSON.
        .executableTarget(
            name: "cspot",
            dependencies: ["CSpotKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
