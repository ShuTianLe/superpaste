// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClipShelf",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ClipShelfCore", targets: ["ClipShelfCore"]),
        .executable(name: "ClipShelf", targets: ["ClipShelfApp"]),
        .executable(name: "ClipShelfCoreSmokeTests", targets: ["ClipShelfCoreSmokeTests"])
    ],
    targets: [
        .target(
            name: "ClipShelfCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("Vision"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "ClipShelfApp",
            dependencies: ["ClipShelfCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "ClipShelfCoreSmokeTests",
            dependencies: ["ClipShelfCore"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
