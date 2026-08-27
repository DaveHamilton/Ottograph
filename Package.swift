// swift-tools-version: 5.9
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
            linkerSettings: [
                // Sparkle.framework is embedded in Contents/Frameworks by
                // Scripts/build-app.sh; without this rpath the app launches
                // straight into a dyld "image not found" crash.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
