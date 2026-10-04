// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "TonkTown",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "TonkTown", targets: ["TonkTown"])],
  dependencies: [
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1")
  ],
  targets: [
    .target(name: "HarnessCore"),
    .executableTarget(
      name: "TonkTown",
      dependencies: [
        "HarnessCore", .product(name: "MarkdownUI", package: "swift-markdown-ui"),
      ]),
    .testTarget(name: "HarnessCoreTests", dependencies: ["HarnessCore"]),
    .testTarget(name: "TonkTownTests", dependencies: ["TonkTown"]),
  ]
)
