// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clippy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Clippy", targets: ["Clippy"]),
        .library(name: "ClippyCore", targets: ["ClippyCore"]),
    ],
    targets: [
        .target(name: "ClippyCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "Clippy", dependencies: ["ClippyCore"]),
        // Plain executable test runner: XCTest/swift-testing need full Xcode, this runs anywhere.
        .executableTarget(name: "ClippyChecks", dependencies: ["ClippyCore"]),
    ]
)
