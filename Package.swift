// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThaiKeyboard",
    platforms: [.macOS("26.0")],
    targets: [
        .target(
            name: "ThaiKeyboardCore"
        ),
        .executableTarget(
            name: "ThaiKeyboard",
            dependencies: ["ThaiKeyboardCore"]
        ),
        .testTarget(
            name: "ThaiKeyboardCoreTests",
            dependencies: ["ThaiKeyboardCore"]
        ),
    ]
)
