// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "KeyboardCore",
    defaultLocalization: "de",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KeyboardCore", targets: ["KeyboardCore"])
    ],
    targets: [
        .target(
            name: "KeyboardCore",
            resources: [.copy("Resources/de_words.txt"), .copy("Resources/de_bigrams.txt"),
                        .copy("Resources/en_words.txt"), .copy("Resources/en_bigrams.txt")],
            // The lexicon loader and decoders are hot paths; keep them optimised in Debug too so
            // the keyboard is responsive while developing (load: ~0.13 s optimised vs. seconds at -Onone).
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release)),
                            .unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
        .testTarget(name: "KeyboardCoreTests", dependencies: ["KeyboardCore"])
    ]
)
