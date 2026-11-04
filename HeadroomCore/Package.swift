// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeadroomCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "HeadroomCore", targets: ["HeadroomCore"])],
    targets: [
        .target(name: "HeadroomCore"),
        .testTarget(name: "HeadroomCoreTests", dependencies: ["HeadroomCore"], resources: [.copy("Fixtures")]),
    ]
)
