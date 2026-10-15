// swift-tools-version: 6.0
import PackageDescription

// Tools version 6.0 makes Swift 6 the language mode of every target below.
// SwiftPM reads the constant by this name.
// swiftlint:disable:next prefixed_toplevel_constant
let package = Package(
    name: "CutawayKit",
    // The interface's text is written in English first (C-LOC-01).
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CutawayUI", targets: ["CutawayUI"]),
        .library(name: "CutawayModel", targets: ["CutawayModel"]),
        .library(name: "CutawayRender", targets: ["CutawayRender"]),
        .library(name: "CutawayTransport", targets: ["CutawayTransport"]),
        .library(name: "CutawayWire", targets: ["CutawayWire"]),
        .library(name: "CutawayTestSupport", targets: ["CutawayTestSupport"]),
    ],
    dependencies: [
        // Must equal Protocol/FLATBUFFERS_VERSION; scripts/check.sh checks that they agree.
        .package(url: "https://github.com/google/flatbuffers.git", exact: "25.12.19"),
        .package(url: "https://github.com/nothingsh/DeclarativeAppKit.git", exact: "0.1.0"),
        .package(url: "https://github.com/nothingsh/DeclarativeCombine.git", exact: "0.2.0"),
    ],
    targets: [
        .target(
            name: "CutawayWire",
            dependencies: [.product(name: "FlatBuffers", package: "flatbuffers")]
        ),
        .target(name: "CutawayTransport", dependencies: ["CutawayWire"]),
        .target(name: "CutawayScene"),
        .target(
            name: "CutawayModel",
            dependencies: ["CutawayScene", "CutawayTransport", "CutawayWire"]
        ),
        .target(
            name: "CutawayRender",
            dependencies: ["CutawayScene"],
            resources: [.process("Shaders")]
        ),
        .target(
            name: "CutawayUI",
            dependencies: [
                "CutawayRender",
                "CutawayScene",
                "CutawayModel",
                "CutawayTransport",
                "CutawayWire",
                .product(name: "DeclarativeAppKit", package: "DeclarativeAppKit"),
                .product(name: "DeclarativeCombine", package: "DeclarativeCombine"),
            ],
            // The licences of the libraries shipped with the app (C-MENU-03).
            // The interface's text in its languages (C-LOC-01).
            // The glyphs of the layers' icons (C-HIER-11), the empty app list's picture (C-LIST-04).
            resources: [
                .copy("Resources/Acknowledgements"), .process("Resources/Localizable.xcstrings"),
                .process("Resources/LayerGlyphs.xcassets"), .process("Resources/Images.xcassets"),
            ]
        ),
        .target(name: "CutawayTestSupport", dependencies: ["CutawayScene", "CutawayWire", "CutawayTransport"]),
        .testTarget(
            name: "CutawayWireTests",
            dependencies: [
                "CutawayWire",
                "CutawayTestSupport",
                .product(name: "FlatBuffers", package: "flatbuffers"),
            ]
        ),
        .testTarget(
            name: "CutawaySceneTests",
            dependencies: ["CutawayScene", "CutawayTestSupport"]
        ),
        .testTarget(
            name: "CutawayRenderTests",
            dependencies: [
                "CutawayRender", "CutawayScene", "CutawayModel", "CutawayWire", "CutawayTestSupport",
            ]
        ),
        .testTarget(
            name: "CutawayUITests",
            dependencies: [
                "CutawayUI",
                "CutawayScene",
                "CutawayRender",
                "CutawayModel",
                "CutawayTransport",
                "CutawayWire",
                "CutawayTestSupport",
                .product(name: "DeclarativeAppKit", package: "DeclarativeAppKit"),
            ]
        ),
        .testTarget(
            name: "CutawayTransportTests",
            dependencies: ["CutawayTransport", "CutawayWire", "CutawayTestSupport"]
        ),
        .testTarget(
            name: "CutawayTestSupportTests",
            dependencies: ["CutawayTestSupport", "CutawayTransport", "CutawayWire"]
        ),
        .testTarget(
            name: "CutawayModelTests",
            dependencies: [
                "CutawayModel", "CutawayScene", "CutawayTransport", "CutawayWire", "CutawayTestSupport",
            ]
        ),
    ]
)
