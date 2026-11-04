// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PriceBar",
    platforms: [.macOS(.v14)],
    targets: [
        // The logic: prices, settings, the rules. No SwiftUI here, so that it
        // is testable and, if the UI is ever rewritten, kept.
        .target(name: "PriceBarCore", path: "Sources/PriceBarCore"),
        // The app: the menu bar item and the panel.
        .executableTarget(
            name: "PriceBar",
            dependencies: ["PriceBarCore"],
            path: "Sources/PriceBar"
        ),
        .testTarget(
            name: "PriceBarCoreTests",
            dependencies: ["PriceBarCore"],
            path: "Tests/PriceBarCoreTests"
        ),
    ]
)
