##  desktoppr

To integrate this into [desktoppr](https://github.com/scriptingosx/desktoppr), you can:

1. Add this package as a dependency
2. Use the `WallpaperFolderManager` class to add/remove folders
3. The library handles all the plist manipulation and service restarts

Example integration:

```swift
import WallpaperFolderManagerLib

func addWallpaperFolder(_ path: String) -> Bool {
    do {
        let manager = try WallpaperFolderManager()
        try manager.addFolderAndApply(path)
        return true
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        return false
    }
}
```