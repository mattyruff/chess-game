// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChessCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "ChessCore", targets: ["ChessCore"])],
    targets: [
        .target(name: "ChessCore"),
        .testTarget(name: "ChessCoreTests", dependencies: ["ChessCore"])
    ]
)
