// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LooiKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LooiKit", targets: ["LooiKit"]),
        .library(name: "LooiKitTesting", targets: ["LooiKitTesting"]),
    ],
    targets: [
        .target(
            name: "LooiKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
        .target(
            name: "LooiKitTesting",
            dependencies: ["LooiKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "LooiKitTests",
            dependencies: ["LooiKit", "LooiKitTesting"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                // Note: defaultIsolation(MainActor.self) is intentionally omitted for the
                // test target — XCTestCase.init() is nonisolated and conflicts with
                // @MainActor default isolation on the subclass initializer.
            ]
        ),
    ]
)
