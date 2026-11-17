// swift-tools-version: 6.4
// AuralCore: all of Aural's logic (playback, Soloist control, library), no UI.
// The SwiftUI app target depends on this package; `swift test` runs its tests.

import PackageDescription

let package = Package(
    name: "AuralCore",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "AuralCore", targets: ["AuralCore"]),
        .executable(name: "aural-probe", targets: ["aural-probe"]),
    ],
    targets: [
        .target(name: "AuralCore"),
        // Small command-line tool used to drive AuralCore before the app exists.
        .executableTarget(name: "aural-probe", dependencies: ["AuralCore"]),
        .testTarget(
            name: "AuralCoreTests",
            dependencies: ["AuralCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
