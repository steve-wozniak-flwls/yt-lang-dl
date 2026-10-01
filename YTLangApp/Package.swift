// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YTLangApp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "YTLangApp",
            path: "YTLangApp"
        ),
    ]
)
