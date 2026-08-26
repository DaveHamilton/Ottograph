// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ottograph",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Ottograph",
            path: "Sources/Ottograph"
        )
    ]
)
