// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexIsland",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CodexIsland", targets: ["CodexIsland"])],
    targets: [
        .target(name: "QuotaCore"),
        .executableTarget(name: "CodexIsland", dependencies: ["QuotaCore"]),
        .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"]),
        .executableTarget(name: "QuotaCheck", dependencies: ["QuotaCore"])
    ]
)
