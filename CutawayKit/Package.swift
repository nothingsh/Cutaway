// swift-tools-version: 6.0
import PackageDescription

// Tools version 6.0 makes Swift 6 the language mode of every target below.
// SwiftPM reads the constant by this name.
// swiftlint:disable:next prefixed_toplevel_constant
let package = Package(
    name: "CutawayKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CutawayTransport", targets: ["CutawayTransport"]),
        .library(name: "CutawayWire", targets: ["CutawayWire"]),
        .library(name: "CutawayTestSupport", targets: ["CutawayTestSupport"]),
    ],
    dependencies: [
        // Must equal Protocol/FLATBUFFERS_VERSION; scripts/check.sh checks that they agree.
        .package(url: "https://github.com/google/flatbuffers.git", exact: "25.12.19"),
    ],
    targets: [
        .target(
            name: "CutawayWire",
            dependencies: [.product(name: "FlatBuffers", package: "flatbuffers")]
        ),
        .target(name: "CutawayTransport", dependencies: ["CutawayWire"]),
        .target(name: "CutawayScene"),
        .target(name: "CutawayTestSupport", dependencies: ["CutawayWire", "CutawayTransport"]),
        .testTarget(
            name: "CutawayWireTests",
            dependencies: [
                "CutawayWire",
                "CutawayTestSupport",
                .product(name: "FlatBuffers", package: "flatbuffers"),
            ]
        ),
        .testTarget(
            name: "CutawayTransportTests",
            dependencies: ["CutawayTransport", "CutawayWire", "CutawayTestSupport"]
        ),
    ]
)
