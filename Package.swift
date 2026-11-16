// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GeometryStudio",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "GeometryStudio", targets: ["GeometryStudio"])
    ],
    targets: [
        .executableTarget(
            name: "GeometryStudio",
            path: "Sources/GeometryStudio"
        )
    ]
)
