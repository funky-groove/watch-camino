// swift-tools-version:5.9
// Núcleo puro de Camino Seguro Watch (docs/WATCH_V1_SPEC.md §1).
// Sólo Foundation: nada de UI, sensores ni plataforma. Sin dependencias externas.
import PackageDescription

let package = Package(
    name: "CaminoCore",
    platforms: [
        .watchOS(.v10),
        .macOS(.v13),
    ],
    products: [
        .library(name: "CaminoCore", targets: ["CaminoCore"]),
    ],
    targets: [
        .target(
            name: "CaminoCore",
            path: "Sources/CaminoCore"
        ),
        .testTarget(
            name: "CaminoCoreTests",
            dependencies: ["CaminoCore"],
            path: "Tests/CaminoCoreTests"
        ),
    ]
)
