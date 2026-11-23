// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HankoMix",
    platforms: [.macOS("14.4")],
    products: [
        .executable(name: "HankoMix", targets: ["HankoMix"]),
        .executable(name: "pav-diag", targets: ["pav-diag"]),
        .executable(name: "autoeq-index", targets: ["autoeq-index"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
    ],
    targets: [
        .target(name: "PAVCore", dependencies: [.product(name: "Atomics", package: "swift-atomics")]),
        .target(name: "PAVAudio", dependencies: ["PAVCore"]),
        .executableTarget(name: "HankoMix", dependencies: ["PAVCore", "PAVAudio"], resources: [.process("Resources")]),
        .executableTarget(name: "pav-diag", dependencies: ["PAVCore", "PAVAudio"]),
        .executableTarget(name: "autoeq-index", dependencies: ["PAVCore"]),
        .testTarget(name: "PAVCoreTests", dependencies: ["PAVCore"]),
        .testTarget(name: "PAVAudioTests", dependencies: ["PAVAudio"]),
    ]
)
