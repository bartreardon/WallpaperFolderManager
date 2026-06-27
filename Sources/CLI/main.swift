//
//  main.swift
//  wallpaper-folder CLI
//
//  Command-line interface for WallpaperFolderManager using Swift Argument Parser
//

import Foundation
import ArgumentParser
import WallpaperFolderManagerLib

@main
struct WallpaperFolderCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wallpaper-folder",
        abstract: "Manage custom wallpaper folders in macOS System Settings",
        discussion: """
            This tool adds one or more custom folder paths to System Settings > Wallpaper:
            
            • macOS 15 (Sequoia) and earlier: UserFolderPaths in system preferences
            • macOS 26 (Tahoe) and later: Wallpaper extension container plist
            
            Folders appear in System Settings > Wallpaper as an additional photo set.
            """,
        version: "1.1.0",
        subcommands: [Add.self, Remove.self, List.self,
                      AddPhoto.self, RemovePhoto.self, ListPhotos.self, ResetPhotos.self]
    )
}

// MARK: - Add Command

struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add a folder to System Settings wallpaper sources"
    )
    
    @Argument(help: "Path to the folder containing images")
    var folder: String
    
    @Flag(name: .shortAndLong, help: "Don't restart wallpaper services after adding")
    var noRestart: Bool = false
    
    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false
    
    mutating func run() throws {
        let manager = try WallpaperFolderManager()
        
        if verbose {
            printVersionInfo(manager: manager)
        }
        
        print("Adding folder: \(folder)")
        
        if noRestart {
            try manager.addFolder(folder)
            print("\n✓ Folder added successfully")
            print("Run 'killall cfprefsd; killall WallpaperAgent' to apply changes")
        } else {
            try manager.addFolderAndApply(folder)
            print("\n✓ Folder added successfully")
        }
        
        print("\nOpen System Settings > Wallpaper to see your folder under 'Your Photos'")
    }
}

// MARK: - Remove Command

struct Remove: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove a folder from System Settings wallpaper sources"
    )
    
    @Argument(help: "Path to the folder to remove")
    var folder: String
    
    @Flag(name: .shortAndLong, help: "Don't restart wallpaper services after removing")
    var noRestart: Bool = false
    
    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false
    
    mutating func run() throws {
        let manager = try WallpaperFolderManager()
        
        if verbose {
            printVersionInfo(manager: manager)
        }
        
        print("Removing folder: \(folder)")
        
        if noRestart {
            try manager.removeFolder(folder)
            print("✓ Folder removed successfully")
            print("Run 'killall cfprefsd; killall WallpaperAgent' to apply changes")
        } else {
            try manager.removeFolderAndApply(folder)
            print("✓ Folder removed successfully")
        }
    }
}

// MARK: - List Command

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all registered wallpaper folders"
    )
    
    @Flag(name: .shortAndLong, help: "Show verbose output including IDs and plist path")
    var verbose: Bool = false
    
    mutating func run() throws {
        let manager = try WallpaperFolderManager()
        
        if verbose {
            printVersionInfo(manager: manager)
            print()
        }
        
        let folders = try manager.listFolders()
        
        if folders.isEmpty {
            print("No wallpaper folders configured.")
            return
        }
        
        print("Registered wallpaper folders (\(folders.count)):")
        print()
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        for (index, folder) in folders.enumerated() {
            print("  \(index + 1). \(folder.path)")
            
            if verbose {
                if let id = folder.id {
                    print("     ID: \(id)")
                }
                if let date = folder.dateAdded {
                    print("     Added: \(formatter.string(from: date))")
                }
            }
            
            if verbose || index < folders.count - 1 {
                print()
            }
        }
    }
}

// MARK: - Add Photo Command

struct AddPhoto: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add-photo",
        abstract: "Add a single image to System Settings > Wallpaper 'Your Photos' (macOS 26+)"
    )

    @Argument(help: "Path to the image file")
    var image: String

    @Flag(name: .shortAndLong, help: "Don't restart wallpaper services after adding")
    var noRestart: Bool = false

    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false

    mutating func run() throws {
        let manager = try WallpaperFolderManager()

        if verbose {
            printVersionInfo(manager: manager)
        }

        print("Adding photo: \(image)")

        if noRestart {
            try manager.addPhoto(image)
            print("\n✓ Photo added successfully")
            print("Run 'killall cfprefsd; killall WallpaperAgent' to apply changes")
        } else {
            try manager.addPhotoAndApply(image)
            print("\n✓ Photo added successfully")
        }

        print("\nOpen System Settings > Wallpaper to see it under 'Your Photos'")
    }
}

// MARK: - Remove Photo Command

struct RemovePhoto: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove-photo",
        abstract: "Remove a single image from 'Your Photos' (macOS 26+)"
    )

    @Argument(help: "Path to the image file to remove")
    var image: String

    @Flag(name: .shortAndLong, help: "Don't restart wallpaper services after removing")
    var noRestart: Bool = false

    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false

    mutating func run() throws {
        let manager = try WallpaperFolderManager()

        if verbose {
            printVersionInfo(manager: manager)
        }

        print("Removing photo: \(image)")

        if noRestart {
            try manager.removePhoto(image)
            print("✓ Photo removed successfully")
            print("Run 'killall cfprefsd; killall WallpaperAgent' to apply changes")
        } else {
            try manager.removePhotoAndApply(image)
            print("✓ Photo removed successfully")
        }
    }
}

// MARK: - List Photos Command

struct ListPhotos: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-photos",
        abstract: "List individual images registered in 'Your Photos' (macOS 26+)"
    )

    @Flag(name: .shortAndLong, help: "Show verbose output including plist path")
    var verbose: Bool = false

    mutating func run() throws {
        let manager = try WallpaperFolderManager()

        if verbose {
            printVersionInfo(manager: manager)
            print()
        }

        let photos = try manager.listPhotos()

        if photos.isEmpty {
            print("No individual photos in 'Your Photos'.")
            return
        }

        print("Photos in 'Your Photos' (\(photos.count)):")
        print()
        for (index, photo) in photos.enumerated() {
            print("  \(index + 1). \(photo.path)")
        }
    }
}

// MARK: - Reset Photos Command

struct ResetPhotos: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reset-photos",
        abstract: "Clear the 'Your Photos' area (macOS 26+)",
        discussion: """
            Clears individual images and Photos-library sources (albums, people)
            from System Settings > Wallpaper 'Your Photos'. This works around the
            macOS bug where the X / right-click "Remove" buttons do nothing.

            By default, custom folders added with 'add' are left in place.
            Use --include-folders to also remove those.
            """
    )

    @Flag(name: .long, help: "Also remove custom folders added with 'add'")
    var includeFolders: Bool = false

    @Flag(name: .shortAndLong, help: "Don't restart wallpaper services after clearing")
    var noRestart: Bool = false

    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false

    mutating func run() throws {
        let manager = try WallpaperFolderManager()

        if verbose {
            printVersionInfo(manager: manager)
            print()
        }

        let before: WallpaperFolderManager.YourPhotosContents
        if noRestart {
            before = try manager.resetYourPhotos(includeFolders: includeFolders)
            print("Run 'killall cfprefsd; killall WallpaperAgent' to apply changes")
        } else {
            before = try manager.resetYourPhotosAndApply(includeFolders: includeFolders)
        }

        print("✓ Cleared 'Your Photos':")
        print("  Individual images: \(before.imageFiles)")
        print("  Photos assets:     \(before.assets)")
        print("  Photos albums:     \(before.collections)")
        print("  Photos people:     \(before.people)")
        if includeFolders {
            print("  Custom folders:    \(before.imageFolders)")
        } else if before.imageFolders > 0 {
            print("\n\(before.imageFolders) custom folder(s) left in place (use --include-folders to remove).")
        }
        print("\nNote: the wallpaper currently applied to your desktop is stored separately")
        print("and won't disappear until you switch to a different background.")
    }
}

// MARK: - Helper Functions

func printVersionInfo(manager: WallpaperFolderManager) {
    let osVersion = ProcessInfo.processInfo.operatingSystemVersion
    let modeDesc = manager.isTahoeOrLater ? "Tahoe+ (wallpaper extension)" : "Legacy (UserFolderPaths)"
    
    print("macOS \(osVersion.majorVersion).\(osVersion.minorVersion) - Using \(modeDesc) mode")
    print("Plist: \(manager.plistPath)")
}
