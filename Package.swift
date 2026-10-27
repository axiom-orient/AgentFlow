// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "AgentFlow",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "AgentFlow", targets: ["AgentFlow"])],
  targets: [
    .target(
      name: "AgentFlow", swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
    .testTarget(name: "AgentFlowTests", dependencies: ["AgentFlow"]),
  ],
  swiftLanguageModes: [.v6]
)
