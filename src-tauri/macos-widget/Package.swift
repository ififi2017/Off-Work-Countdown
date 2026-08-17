// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WidgetSnapshotContract",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "WidgetSnapshotContract",
            targets: ["WidgetSnapshotContract"]
        ),
        .library(
            name: "OffWorkCountdownWidgetUI",
            targets: ["OffWorkCountdownWidgetUI"]
        )
    ],
    targets: [
        .target(
            name: "WidgetSnapshotContract"
        ),
        .target(
            name: "OffWorkCountdownWidgetUI",
            dependencies: ["WidgetSnapshotContract"],
            swiftSettings: [.define("OWC_SWIFT_PACKAGE")]
        ),
        .testTarget(
            name: "WidgetSnapshotContractTests",
            dependencies: [
                "WidgetSnapshotContract",
                "OffWorkCountdownWidgetUI"
            ],
            resources: [.copy("Fixtures")]
        )
    ]
)
