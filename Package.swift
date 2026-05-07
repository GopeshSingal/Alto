// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Alto",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Alto", targets: ["Alto"])
    ],
    targets: [
        .executableTarget(
            name: "Alto",
            path: "src/Alto"
        )
    ]
)
