// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Ajar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "AjarShared"),
        .executableTarget(name: "Ajar", dependencies: ["AjarShared"]),
        .executableTarget(name: "AjarHelper", dependencies: ["AjarShared"]),
    ]
)
