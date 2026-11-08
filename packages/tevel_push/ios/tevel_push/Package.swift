// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "tevel_push",
  platforms: [.iOS("13.0")],
  products: [.library(name: "tevel-push", targets: ["tevel_push"])],
  dependencies: [],
  targets: [.target(name: "tevel_push", dependencies: [])]
)
