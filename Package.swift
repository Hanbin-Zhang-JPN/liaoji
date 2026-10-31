// swift-tools-version: 5.9
import PackageDescription

let package = Package(name: "ChatScribe", platforms: [.macOS(.v14)], products: [
    .executable(name: "ChatScribe", targets: ["ChatScribe"])
], targets: [
    .target(name: "ChatCore", resources: [.process("Resources")]),
    .executableTarget(name: "ChatScribe", dependencies: ["ChatCore"]),
    .executableTarget(name: "CoreChecks", dependencies: ["ChatCore"], path: "Tests/CoreChecks")
])
