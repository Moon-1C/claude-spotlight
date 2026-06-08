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
        // Raycast-style GUI (runs unbundled via SwiftPM — no full Xcode needed):
        // menu bar + ⌥Space global hotkey + floating SwiftUI search panel.
        .executableTarget(
            name: "cspot-ui",
            dependencies: ["CSpotKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
