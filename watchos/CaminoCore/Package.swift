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
        .library(name: "CaminoDesign", targets: ["CaminoDesign"]),
    ],
    targets: [
        .target(
            name: "CaminoCore",
            path: "Sources/CaminoCore"
        ),
        // Tokens de diseño como datos puros, para verificar el contraste con tests.
        .target(
            name: "CaminoDesign",
            path: "Sources/CaminoDesign"
        ),
        .testTarget(
            name: "CaminoDesignTests",
            dependencies: ["CaminoDesign"],
            path: "Tests/CaminoDesignTests"
        ),
        .testTarget(
            name: "CaminoCoreTests",
            dependencies: ["CaminoCore"],
            path: "Tests/CaminoCoreTests"
        ),
    ]
)
