// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Watt",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CSMC", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "Watt", dependencies: ["CSMC"]),
    ]
)
