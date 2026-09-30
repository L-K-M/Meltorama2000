// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Meltorama",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Meltorama", targets: ["MeltoramaMac"])],
    targets: [
        .target(name: "MeltoramaCore"),
        .executableTarget(name: "MeltoramaMac", dependencies: ["MeltoramaCore"],
                          resources: [.process("Resources")],
                          linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("OpenGL"),
                                           .linkedFramework("AVFoundation")]),
        .testTarget(name: "MeltoramaCoreTests", dependencies: ["MeltoramaCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "MeltoramaMacTests", dependencies: ["MeltoramaMac", "MeltoramaCore"])
    ],
    swiftLanguageModes: [.v5]
)
