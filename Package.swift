// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "TonkTown",
  platforms: [.macOS("15.0")],
  products: [.executable(name: "TonkTown", targets: ["TonkTown"])],
  dependencies: [
    .package(url: "https://github.com/gonzalezreal/textual", from: "0.5.0")
  ],
  targets: [
    .target(name: "HarnessCore"),
    .executableTarget(
      name: "TonkTown",
      dependencies: [
        "HarnessCore", .product(name: "Textual", package: "textual"),
      ]),
    .testTarget(name: "HarnessCoreTests", dependencies: ["HarnessCore"]),
    .testTarget(name: "TonkTownTests", dependencies: ["TonkTown"]),
  ]
)
