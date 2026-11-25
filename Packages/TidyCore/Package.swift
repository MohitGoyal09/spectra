// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TidyCore",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "TidyCore", targets: ["TidyCore"])],
    targets: [
        .target(name: "TidyCore"),
        .testTarget(name: "TidyCoreTests", dependencies: ["TidyCore"]),
    ]
)
