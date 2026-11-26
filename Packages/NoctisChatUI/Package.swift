// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NoctisChatUI",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26), .visionOS(.v26)],
    products: [.library(name: "NoctisChatUI", targets: ["NoctisChatUI"])],
    targets: [
        .target(name: "NoctisChatUI", resources: [.process("Resources")])
    ]
)
