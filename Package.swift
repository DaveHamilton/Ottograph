// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ottograph",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "Ottograph",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Ottograph",
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                // Sparkle.framework is embedded in Contents/Frameworks by
                // Scripts/build-app.sh; without this rpath the app launches
                // straight into a dyld "image not found" crash.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        // Covers the pure logic only — the parsing, the clamping, and the
        // config/UI conversions. The engine itself can't be unit tested:
        // its whole job is a conversation with a running Mail. What it
        // *can* do is stop those conversions from breaking in silence.
        .testTarget(
            name: "OttographTests",
            dependencies: ["Ottograph"],
            path: "Tests/OttographTests"
        )
    ]
)
