// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "BikeBuddy", platforms: [.macOS(.v14)],
  targets: [.executableTarget(name: "BikeBuddy", path: "Sources")])
