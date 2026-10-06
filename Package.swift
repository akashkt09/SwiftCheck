// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftCheck",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QACore", targets: ["QACore"]),
        .executable(name: "swiftcheck", targets: ["swiftcheck"]),
        .executable(name: "SwiftCheckApp", targets: ["SwiftCheckApp"])
    ],
    targets: [
        .target(name: "QACore"),
        .executableTarget(name: "swiftcheck", dependencies: ["QACore"]),
        .executableTarget(name: "SwiftCheckApp", dependencies: ["QACore"])
    ]
)
