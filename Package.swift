// swift-tools-version: 6.0
import PackageDescription

// HashlineCore holds everything that must be testable without UI (codec, parser, styling, HTML).
// The app target lives in Sources/Hashline and is built from project.yml (XcodeGen).
let package = Package(
    name: "Hashline",
    platforms: [.macOS(.v14)],
    products: [
        // Dynamic: the app and its Quick Look extension share one copy (static linking put a second
        // 4 MB copy of the parser and renderer into the extension).
        .library(name: "HashlineCore", type: .dynamic, targets: ["HashlineCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0"),
    ],
    targets: [
        .target(name: "HashlineCore", dependencies: [.product(name: "Markdown", package: "swift-markdown")],
                resources: [.copy("Resources/highlight.min.js"), .copy("Resources/emoji.json"),
                            .copy("Resources/katex.min.js")]),
        .testTarget(name: "HashlineCoreTests", dependencies: ["HashlineCore"], resources: [.copy("Resources")]),
    ]
)
