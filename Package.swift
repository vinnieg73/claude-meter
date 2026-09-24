// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudeMeter",
    platforms: [.macOS(.v14)],
    targets: [
        // The menu bar app.
        .executableTarget(name: "ClaudeMeter", path: "Sources/ClaudeMeter"),
        // Claude Code statusline command: saves the exact rate_limits block for the app.
        .executableTarget(name: "claude-meter-tap", path: "Sources/Tap"),
    ]
)
