// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HandbyteCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HandbyteCore", targets: ["HandbyteCore"]),
        .library(name: "HandbyteUI", targets: ["HandbyteUI"]),
        .executable(name: "hbscan", targets: ["hbscan"]),
    ],
    targets: [
        // The catalog is a byte-identical copy of `catalog/` in the CLI
        // repository; `scripts/sync-check.sh` compares the two.
        .target(name: "HandbyteCore", resources: [.copy("Resources/catalog")]),
        // Selection, grouping and report logic for the app. No AppKit or
        // SwiftUI so it is testable with `swift test`.
        .target(name: "HandbyteUI", dependencies: ["HandbyteCore"]),
        .executableTarget(name: "hbscan", dependencies: ["HandbyteCore"]),
        .testTarget(name: "HandbyteCoreTests", dependencies: ["HandbyteCore"], resources: [.copy("Conformance")]),
        .testTarget(name: "HandbyteUITests", dependencies: ["HandbyteUI"]),
    ],
    swiftLanguageModes: [.v6]
)
