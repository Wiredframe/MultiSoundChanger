// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MultiSoundChanger",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(name: "MultiSoundChanger", path: "Sources/MultiSoundChanger")
    ]
)
