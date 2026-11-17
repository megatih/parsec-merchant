// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-2.0-or-later
import PackageDescription

let strict: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "ParsecKit",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "ParsecEngine", targets: ["ParsecEngine"]),
        .library(name: "ParsecPersistence", targets: ["ParsecPersistence"]),
        .library(name: "ParsecInsights", targets: ["ParsecInsights"]),
        .library(name: "ParsecArt", targets: ["ParsecArt"]),
        .library(name: "ParsecAudio", targets: ["ParsecAudio"]),
        .executable(name: "pmsim", targets: ["pmsim"]),
        .executable(name: "pmart", targets: ["pmart"]),
    ],
    targets: [
        .target(name: "ParsecEngine", swiftSettings: strict),
        .target(name: "ParsecPersistence", dependencies: ["ParsecEngine", "ParsecInsights"], swiftSettings: strict),
        .target(name: "ParsecInsights", dependencies: ["ParsecEngine"], swiftSettings: strict),
        .target(name: "ParsecArt", swiftSettings: strict),
        .target(name: "ParsecAudio", swiftSettings: strict),
        .executableTarget(name: "pmsim", dependencies: ["ParsecEngine", "ParsecPersistence", "ParsecInsights"], swiftSettings: strict),
        .executableTarget(name: "pmart", dependencies: ["ParsecArt"], swiftSettings: strict),
        .testTarget(name: "ParsecEngineTests", dependencies: ["ParsecEngine"], resources: [.copy("Fixtures")], swiftSettings: strict),
        .testTarget(name: "ParsecScenarioTests", dependencies: ["ParsecEngine"], swiftSettings: strict),
        .testTarget(name: "ParsecPersistenceTests", dependencies: ["ParsecPersistence", "ParsecEngine", "ParsecInsights"],
                    swiftSettings: strict),
        .testTarget(name: "ParsecInsightsTests", dependencies: ["ParsecInsights", "ParsecEngine"], swiftSettings: strict),
        .testTarget(name: "ParsecArtTests", dependencies: ["ParsecArt"], swiftSettings: strict),
        .testTarget(name: "ParsecAudioTests", dependencies: ["ParsecAudio"], swiftSettings: strict),
    ],
    swiftLanguageModes: [.v6]
)
