// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacPulse",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacPulse", targets: ["MacPulse"])],
    targets: [
        .target(name: "MacPulseCore", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("SystemConfiguration")]),
        .executableTarget(name: "MacPulse", dependencies: ["MacPulseCore"], linkerSettings: [.linkedFramework("AppKit")]),
        .testTarget(name: "MacPulseCoreTests", dependencies: ["MacPulseCore"])
    ]
)
