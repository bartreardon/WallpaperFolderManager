// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WallpaperFolderManager",
    platforms: [
        .macOS(.v13)  // macOS Ventura minimum, but Tahoe-specific code path for 26+
    ],
    products: [
        // Library for integration into other projects (like desktoppr)
        .library(
            name: "WallpaperFolderManagerLib",
            targets: ["WallpaperFolderManagerLib"]
        ),
        // Standalone CLI tool
        .executable(
            name: "wallpaper-folder",
            targets: ["wallpaper-folder"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0")
    ],
    targets: [
        // Reusable library
        .target(
            name: "WallpaperFolderManagerLib",
            path: "Sources/WallpaperFolderManagerLib"
        ),
        // CLI executable
        .executableTarget(
            name: "wallpaper-folder",
            dependencies: [
                "WallpaperFolderManagerLib",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/CLI"
        )
    ]
)
