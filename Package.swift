// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MelismaKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MelismaKit", targets: ["MelismaKit"]),
        .library(name: "MelismaKitSwiftUI", targets: ["MelismaKitSwiftUI"]),
        .executable(name: "MelismaKitDemo", targets: ["MelismaKitDemo"]),
        .executable(name: "MelismaKitProbe", targets: ["MelismaKitProbe"]),
        .executable(name: "MelismaKitBench", targets: ["MelismaKitBench"]),
        .executable(name: "MelismaKitParity", targets: ["MelismaKitParity"])
    ],
    targets: [
        .target(name: "MelismaKit"),
        .target(name: "MelismaKitSwiftUI", dependencies: ["MelismaKit"]),
        .executableTarget(name: "MelismaKitDemo", dependencies: ["MelismaKit"], resources: [.copy("Resources")]),
        .executableTarget(name: "MelismaKitProbe", dependencies: ["MelismaKit", "MelismaKitBenchCore"]),
        .target(name: "MelismaKitBenchCore", dependencies: ["MelismaKit"]),
        .executableTarget(name: "MelismaKitBench", dependencies: ["MelismaKit", "MelismaKitBenchCore"]),
        .executableTarget(name: "MelismaKitParity", dependencies: ["MelismaKit", "MelismaKitBenchCore"]),
        .testTarget(name: "MelismaKitTests", dependencies: ["MelismaKit", "MelismaKitBenchCore"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5]
)
