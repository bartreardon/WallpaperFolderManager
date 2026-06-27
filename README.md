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

Download from the [releases page](https://github.com/bartreardon/WallpaperFolderManager/releases) as a PKG installer or standalone binary.

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

### Managing "Your Photos" (macOS 26 / Tahoe and later)

In addition to folders, the System Settings > Wallpaper "Your Photos" area can hold
individual images and Photos-library sources.

```bash
# List individual images registered in "Your Photos"
wallpaper-folder list-photos

# Add a single image to "Your Photos"
wallpaper-folder add-photo ~/Pictures/example.jpg

# Remove a single image
wallpaper-folder remove-photo ~/Pictures/example.jpg

# Clear "Your Photos" — removes individual images and Photos albums/people,
# but leaves any folders added with `add` in place
wallpaper-folder reset-photos

# Clear everything, including custom folders
wallpaper-folder reset-photos --include-folders
```

> **Note:** The wallpaper currently applied to the desktop is stored separately from this
> list, so it won't disappear until the user switches to a different wallpaper.

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

    // --- "Your Photos" individual images (macOS 26 / Tahoe and later) ---

    // Add or remove a single image
    try manager.addPhotoAndApply("/path/to/image.jpg")
    try manager.removePhotoAndApply("/path/to/image.jpg")

    // List individual images
    let photos = try manager.listPhotos()

    // Inspect what's populating "Your Photos"
    let contents = try manager.yourPhotosContents()
    print("\(contents.imageFiles) images, \(contents.imageFolders) folders, \(contents.total) total")

    // Clear "Your Photos" (keeps folders unless includeFolders: true)
    try manager.resetYourPhotosAndApply()

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

The "Your Photos" area is the union of several arrays in the same plist:

- `ChoiceRequests.ImageFolders` — custom folders (managed by `add`/`remove`)
- `ChoiceRequests.ImageFiles` — individual images (managed by `add-photo`/`remove-photo`)
- `ChoiceRequests.Assets` / `ChoiceRequests.CollectionIdentifiers` / `ChoiceRequests.PersonIdentifiers` — Photos-library assets, albums, and people

Each `ImageFiles` entry mirrors a folder entry but uses `copyURL` (instead of `cloneURL`) and `originatingBundleIdentifier` / `originatingBundleName` (instead of `id`). The library preserves all of these arrays and the `DidPerform*Migration` flags on every write, so managing one source never disturbs the others.

## Troubleshooting

### Folder doesn't appear in System Settings

1. Make sure the wallpaper services were restarted:
   ```bash
   killall cfprefsd; killall WallpaperAgent
   ```

2. Try closing and reopening System Settings

3. Check that the folder exists and contains image files

### "Your Photos" images won't delete

On macOS Tahoe, the **X** and right-click **Remove** buttons in the "Your Photos" panel
often don't actually remove anything. Use `wallpaper-folder reset-photos` (or `remove-photo`
for a single image) to clear them, then reopen System Settings.

If an image still won't go away, it's almost certainly the wallpaper **currently applied**
to your desktop — that's stored separately from the picker list. Switch to a different
background first, then run the command again.

## License

MIT License - See LICENSE file for details.

## Contributing

Contributions welcome! Please open an issue or PR on GitHub.
