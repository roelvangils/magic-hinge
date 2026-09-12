// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MagicHinge",
    defaultLocalization: "en",
    platforms: [.macOS("14.2")],
    products: [.executable(name: "MagicHinge", targets: ["MagicHinge"])],
    dependencies: [
        .package(url: "https://github.com/jaywcjlove/PermissionFlow.git", exact: "2.11.2"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.6")
    ],
    targets: [
        .target(name: "DuoCore", resources: [.process("Resources")]),
        .target(name: "DuoHardware", dependencies: ["DuoCore"]),
        .target(name: "DuoGraphics", dependencies: ["DuoCore"], resources: [.copy("Resources/Fold.metal")]),
        .target(name: "DuoSimulation", dependencies: ["DuoCore", "DuoGraphics"], resources: [.copy("Resources/studio_small_09_1k.hdr"), .copy("Resources/AppleModels.json"), .copy("Resources/snap.aiff")]),
        .executableTarget(name: "MagicHinge", dependencies: ["DuoCore", "DuoHardware", "DuoGraphics", "DuoSimulation", .product(name: "PermissionFlow", package: "PermissionFlow"), .product(name: "PermissionFlowScreenRecordingStatus", package: "PermissionFlow"), .product(name: "Sparkle", package: "Sparkle")], exclude:["Resources/DesertWallpaper.jpg", "Resources/DuoNight.jpg"], resources: [.copy("Resources/BasicAppleGuy.png"), .copy("Resources/DuoDay.jpg"), .copy("Resources/DuoNightStarless.jpg"), .process("Resources/en.lproj"), .process("Resources/nl.lproj")]),
        .testTarget(name: "MagicHingeTests", dependencies: ["MagicHinge"]),
        .testTarget(name: "DuoCoreTests", dependencies: ["DuoCore"]),
        .testTarget(name: "DuoSimulationTests", dependencies: ["DuoSimulation", "DuoGraphics"]),
        .testTarget(name: "DuoGraphicsTests", dependencies: ["DuoGraphics", "DuoCore"])
    ],
    swiftLanguageModes: [.v5]
)
