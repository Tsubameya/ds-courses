// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TrainerCapture",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "TrainerCapture", targets: ["TrainerCapture"]),
    ],
    targets: [
        .target(name: "TrainerCapture"),
        .testTarget(name: "TrainerCaptureTests", dependencies: ["TrainerCapture"]),
    ]
)
