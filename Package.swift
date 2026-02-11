// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Typist",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TypistCore", targets: ["TypistCore"]),
        .executable(name: "TypistMenuBar", targets: ["TypistMenuBar"])
    ],
    targets: [
        .target(
            name: "TypistCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "TypistMenuBar",
            dependencies: ["TypistCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Charts")
            ]
        ),
        .testTarget(
            name: "TypistCoreTests",
            dependencies: ["TypistCore"]
        )
    ]
)
