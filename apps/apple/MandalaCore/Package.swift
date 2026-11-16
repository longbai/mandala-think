// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MandalaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MandalaCore", targets: ["MandalaCore"])],
    dependencies: [
        .package(path: "Vendor/Yams"),
        .package(path: "Vendor/ZIPFoundation")
    ],
    targets: [
        .target(name: "MandalaCore", dependencies: ["Yams", "ZIPFoundation"]),
        .testTarget(name: "MandalaCoreTests", dependencies: ["MandalaCore", "ZIPFoundation"],
                    resources: [.copy("Fixtures/sample.mandala")])
    ]
)
