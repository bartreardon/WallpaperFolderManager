# WallpaperFolderManager

A Swift library and CLI tool for programmatically adding custom wallpaper folders to macOS System Settings.

## Background

This library handles wallpaper folder management across different macOS versions:

- **macOS 15 (Sequoia) and earlier**: Uses the `UserFolderPaths` array in `~/Library/Preferences/com.apple.systempreferences.plist`
- **macOS 26 (Tahoe) and later**: Uses the `com.apple.wallpaper.extension.image` container plist with a new binary format

The library automatically detects your macOS version and uses the appropriate method.

## Requirements

- macOS Ventura (13.0) or later
- Swift 5.9+

## Installation

### Standalone utility

#### PKG Installer

Download from the [releases page](https://github.com/bartreardon/WallpaperFolderManager/releases) as a PKG installer or standalone binary.

#### Homebrew

```
brew tap bartreardon/cask
brew install --cask wallpaper-folder
```

### As a Swift Package Dependency

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/bartreardon/WallpaperFolderManager.git", from: "1.0.0")
]
```

Then add `WallpaperFolderManagerLib` as a dependency to your target.

### Building the CLI Tool

```bash
swift build -c release
# Binary will be at .build/release/wallpaper-folder
```

## CLI Usage

```bash
# Add a folder
wallpaper-folder add ~/Pictures/Wallpapers

# Add a folder with verbose output
wallpaper-folder add ~/Pictures/Wallpapers --verbose

# Add a folder without restarting services
wallpaper-folder add ~/Pictures/Wallpapers --no-restart

# List registered folders
wallpaper-folder list

# List with verbose output (shows IDs and dates)
wallpaper-folder list --verbose

# Remove a folder
wallpaper-folder remove ~/Pictures/Wallpapers

# Show help
wallpaper-folder --help
wallpaper-folder add --help
```

## Library Usage

```swift
import WallpaperFolderManagerLib

do {
    let manager = try WallpaperFolderManager()
    
    // Add a folder (and restart services to apply)
    try manager.addFolderAndApply("/path/to/folder")
    
    // Or add without restarting (useful for batch operations)
    try manager.addFolder("/path/to/folder1")
    try manager.addFolder("/path/to/folder2")
    manager.restartServices()
    
    // List all registered folders
    let folders = try manager.listFolders()
    for folder in folders {
        print("\(folder.path) - Added: \(folder.dateAdded)")
    }
    
    // Check if a folder is registered
    if try manager.isFolderRegistered("/path/to/folder") {
        print("Folder is registered")
    }
    
    // Remove a folder
    try manager.removeFolderAndApply("/path/to/folder")
    
} catch {
    print("Error: \(error.localizedDescription)")
}
```

## How It Works

### macOS 15 (Sequoia) and Earlier

Folders are stored in `~/Library/Preferences/com.apple.systempreferences.plist` under the `UserFolderPaths` key as a simple array of path strings.

### macOS 26 (Tahoe) and Later

The wallpaper extension stores folder configuration in:
```
~/Library/Containers/com.apple.wallpaper.extension.image/Data/Library/Preferences/com.apple.wallpaper.extension.image.plist
```

Each folder entry is stored as a binary plist blob containing:
- `id`: A UUID for the entry
- `dateAdded`: When the folder was added
- `originalURL`: The file:// URL to the actual folder
- `originalURLBookmarkData`: macOS bookmark data for sandbox access
- `cloneURL`: A cache location in /var/folders

**Important**: The keys must be in a specific order in the binary plist. This library handles that automatically using `PropertyListSerialization` with `NSMutableDictionary`.

## Troubleshooting

### Folder doesn't appear in System Settings

1. Make sure the wallpaper services were restarted:
   ```bash
   killall cfprefsd; killall WallpaperAgent
   ```

2. Try closing and reopening System Settings

3. Check that the folder exists and contains image files

## License

MIT License - See LICENSE file for details.

## Contributing

Contributions welcome! Please open an issue or PR on GitHub.
