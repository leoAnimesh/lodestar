// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lodestar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Lodestar", targets: ["Lodestar"]),
        .library(name: "LodestarCore", targets: ["LodestarCore"]),
    ],
    targets: [
        // Pure-Swift logic (no AppKit): matching, ranking, calculator,
        // hotkey parsing, script metadata, extension wire protocol.
        .target(name: "LodestarCore"),
        // The macOS menu-bar app: panel, hotkey, providers, extension host.
        .executableTarget(
            name: "Lodestar",
            dependencies: ["LodestarCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "LodestarCoreTests", dependencies: ["LodestarCore"]),
    ]
)
