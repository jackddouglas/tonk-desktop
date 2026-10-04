// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "TonkTown",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "TonkTown", targets: ["TonkTown"])],
  targets: [
    .target(name: "HarnessCore"),
    .executableTarget(name: "TonkTown", dependencies: ["HarnessCore"]),
    .testTarget(name: "HarnessCoreTests", dependencies: ["HarnessCore"]),
    .testTarget(name: "TonkTownTests", dependencies: ["TonkTown"]),
  ]
)
