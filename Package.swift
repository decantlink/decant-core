// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "DecantCore",
  platforms: [.macOS(.v13), .iOS(.v16), .macCatalyst(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
  products: [
    .library(name: "DecantCore", targets: ["DecantCore"]),
    .library(name: "DecantCoreFoundation", targets: ["DecantCoreFoundation"]),
  ],
  targets: [
    // Pure engine. Foundation only (URL/Data/Date). No CryptoKit, no UIKit/SwiftUI/AppKit.
    .target(name: "DecantCore"),
    // Apple-platform adapters: the CryptoKit-backed signature verifier lives here so the
    // pure engine stays portable and crypto-free.
    .target(name: "DecantCoreFoundation", dependencies: ["DecantCore"]),
    .testTarget(
      name: "DecantCoreTests",
      dependencies: ["DecantCore", "DecantCoreFoundation"],
      resources: [
        .copy("Resources/rules.bundle.json"),
        .copy("Resources/url-fidelity.json"),
        .copy("Resources/semantic-safety.json"),
      ]
    ),
  ]
)
