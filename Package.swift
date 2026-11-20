// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FellowshipDesktop",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FellowshipDesktop",
            path: "Sources/FellowshipDesktop"
        ),
        .testTarget(
            name: "FellowshipDesktopTests",
            dependencies: ["FellowshipDesktop"],
            path: "Tests/FellowshipDesktopTests"
        ),
    ]
)
