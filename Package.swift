// swift-tools-version: 6.0
import PackageDescription

// The launcher is a plain macOS app: no runtime to install, no extra toolchain. The build pipeline it
// drives is Python + Xcode, both already on the machine (see bootstrap.sh).
let package = Package(
    name: "NxLauncher",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NxLauncher",
            path: "Sources/NxLauncher"
        )
    ],
    swiftLanguageModes: [.v5]   // the process plumbing predates Swift 6's strict concurrency; keep it simple
)
