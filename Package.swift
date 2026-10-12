// swift-tools-version: 5.9
// Lets the platform-independent core (models, API client, parsers) be tested on the Mac with
// `swift test`. The app itself is built from 30nama.xcodeproj, which compiles the same sources.
import PackageDescription

let package = Package(
    name: "NamaCore",
    platforms: [.macOS(.v13), .tvOS(.v17)],
    products: [.library(name: "NamaCore", targets: ["NamaCore"])],
    targets: [
        .target(name: "NamaCore", path: "30nama/Core"),
        .testTarget(
            name: "NamaCoreTests",
            dependencies: ["NamaCore"],
            path: "Tests/NamaCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
