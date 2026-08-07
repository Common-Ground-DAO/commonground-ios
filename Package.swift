// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CommonGroundKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "CommonGroundKit", targets: ["CommonGroundKit"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/socketio/socket.io-client-swift.git",
            exact: "16.1.1"
        )
    ],
    targets: [
        .target(
            name: "CommonGroundKit",
            dependencies: [
                .product(name: "SocketIO", package: "socket.io-client-swift")
            ]
        ),
        .testTarget(
            name: "CommonGroundKitTests",
            dependencies: ["CommonGroundKit"]
        )
    ]
)
