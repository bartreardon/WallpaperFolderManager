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
        version: "1.0.2",
        subcommands: [Add.self, Remove.self, List.self]
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

// MARK: - Helper Functions

func printVersionInfo(manager: WallpaperFolderManager) {
    let osVersion = ProcessInfo.processInfo.operatingSystemVersion
    let modeDesc = manager.isTahoeOrLater ? "Tahoe+ (wallpaper extension)" : "Legacy (UserFolderPaths)"
    
    print("macOS \(osVersion.majorVersion).\(osVersion.minorVersion) - Using \(modeDesc) mode")
    print("Plist: \(manager.plistPath)")
}
