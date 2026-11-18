// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dockinator",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Dockinator", path: "Sources/Dockinator"),
        .testTarget(name: "DockinatorTests", dependencies: ["Dockinator"], path: "Tests"),
    ]
)
