//
//  WallpaperFolderManager.swift
//
//  A module for managing custom wallpaper folders in macOS.
//  
//  - macOS 15 (Sequoia) and earlier: Uses UserFolderPaths in com.apple.systempreferences.plist
//  - macOS 26 (Tahoe) and later: Uses com.apple.wallpaper.extension.image container plist
//
//  Usage:
//      let manager = try WallpaperFolderManager()
//      try manager.addFolder("/path/to/folder")
//      try manager.removeFolder("/path/to/folder")
//      let folders = try manager.listFolders()
//

import Foundation

// MARK: - Public Data Structures

/// Represents a registered wallpaper folder
public struct WallpaperFolder {
    public let id: String?
    public let path: String
    public let dateAdded: Date?
    
    public init(id: String? = nil, path: String, dateAdded: Date? = nil) {
        self.id = id
        self.path = path
        self.dateAdded = dateAdded
    }
}

/// Errors that can occur during wallpaper folder management
public enum WallpaperFolderError: Error, LocalizedError {
    case couldNotGetCacheDirectory
    case notADirectory(String)
    case notAFile(String)
    case folderAlreadyExists(String)
    case folderNotFound(String)
    case photoAlreadyExists(String)
    case photoNotFound(String)
    case plistEncodingError(String)
    case plistReadError(String)
    case bookmarkCreationFailed(String)
    case notSupportedOnThisOS(String)

    public var errorDescription: String? {
        switch self {
        case .couldNotGetCacheDirectory:
            return "Could not determine user cache directory"
        case .notADirectory(let path):
            return "'\(path)' is not a valid directory"
        case .notAFile(let path):
            return "'\(path)' is not a valid file"
        case .folderAlreadyExists(let path):
            return "Folder '\(path)' is already registered"
        case .folderNotFound(let path):
            return "Folder '\(path)' not found in registered folders"
        case .photoAlreadyExists(let path):
            return "Photo '\(path)' is already in Your Photos"
        case .photoNotFound(let path):
            return "Photo '\(path)' not found in Your Photos"
        case .plistEncodingError(let details):
            return "Failed to encode plist: \(details)"
        case .plistReadError(let details):
            return "Failed to read plist: \(details)"
        case .bookmarkCreationFailed(let details):
            return "Failed to create bookmark: \(details)"
        case .notSupportedOnThisOS(let details):
            return details
        }
    }
}

// MARK: - WallpaperFolderManager

/// Manages custom wallpaper folders for macOS System Settings/Preferences
public class WallpaperFolderManager {
    
    /// Whether we're running on macOS Tahoe (26) or later
    public let isTahoeOrLater: Bool
    
    /// Path to the relevant preferences plist
    public let plistPath: String
    
    /// Base path for the cache directory (Tahoe only)
    public let cacheBasePath: String?
    
    /// Initialize the manager, automatically detecting the macOS version
    public init() throws {
        // Check if we're on macOS 26 (Tahoe) or later
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        isTahoeOrLater = osVersion.majorVersion >= 26
        
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        
        if isTahoeOrLater {
            // Tahoe+ uses the wallpaper extension container
            plistPath = "\(home)/Library/Containers/com.apple.wallpaper.extension.image/Data/Library/Preferences/com.apple.wallpaper.extension.image.plist"
            cacheBasePath = try Self.getCacheDirectory()
        } else {
            // Pre-Tahoe uses system preferences plist with UserFolderPaths
            plistPath = "\(home)/Library/Preferences/com.apple.systempreferences.plist"
            cacheBasePath = nil
        }
    }
    
    /// Initialize with explicit mode (useful for testing)
    public init(useTahoeMode: Bool, plistPath: String, cacheBasePath: String? = nil) {
        self.isTahoeOrLater = useTahoeMode
        self.plistPath = plistPath
        self.cacheBasePath = cacheBasePath
    }
    
    // MARK: - Public Methods
    
    /// Add a folder to System Settings wallpaper sources
    public func addFolder(_ folderPath: String) throws {
        let normalizedPath = normalizePath(folderPath)
        
        // Validate folder exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw WallpaperFolderError.notADirectory(folderPath)
        }
        
        if isTahoeOrLater {
            try addFolderTahoe(normalizedPath)
        } else {
            try addFolderLegacy(normalizedPath)
        }
    }
    
    /// Remove a folder from System Settings wallpaper sources
    public func removeFolder(_ folderPath: String) throws {
        let normalizedPath = normalizePath(folderPath)
        
        if isTahoeOrLater {
            try removeFolderTahoe(normalizedPath)
        } else {
            try removeFolderLegacy(normalizedPath)
        }
    }
    
    /// List all registered wallpaper folders
    public func listFolders() throws -> [WallpaperFolder] {
        if isTahoeOrLater {
            return try listFoldersTahoe()
        } else {
            return try listFoldersLegacy()
        }
    }
    
    /// Check if a folder is already registered
    public func isFolderRegistered(_ folderPath: String) throws -> Bool {
        let normalizedPath = normalizePath(folderPath)
        let folders = try listFolders()
        return folders.contains { normalizePath($0.path) == normalizedPath }
    }
    
    // MARK: - "Your Photos" individual images (Tahoe+)

    /// Add a single image file to the "Your Photos" area.
    /// Only supported on macOS Tahoe (26) and later.
    public func addPhoto(_ imagePath: String) throws {
        guard isTahoeOrLater else {
            throw WallpaperFolderError.notSupportedOnThisOS("Adding individual photos requires macOS 26 (Tahoe) or later")
        }

        let normalizedPath = normalizePath(imagePath)

        // Validate the file exists and is a regular file (not a directory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw WallpaperFolderError.notAFile(imagePath)
        }

        var plist = try loadTahoePlist()

        if try photoExistsTahoe(normalizedPath, in: plist) {
            throw WallpaperFolderError.photoAlreadyExists(normalizedPath)
        }

        let entryData = try createTahoePhotoEntry(for: normalizedPath)
        plist.choiceRequestsImageFiles.append(entryData)

        try saveTahoePlist(plist)
    }

    /// Remove a single image file from the "Your Photos" area.
    public func removePhoto(_ imagePath: String) throws {
        guard isTahoeOrLater else {
            throw WallpaperFolderError.notSupportedOnThisOS("Managing individual photos requires macOS 26 (Tahoe) or later")
        }

        let normalizedPath = normalizePath(imagePath)
        var plist = try loadTahoePlist()

        let originalCount = plist.choiceRequestsImageFiles.count
        plist.choiceRequestsImageFiles.removeAll { entryData in
            guard let path = pathFromEntryData(entryData) else { return false }
            return normalizePath(path) == normalizedPath
        }

        guard plist.choiceRequestsImageFiles.count < originalCount else {
            throw WallpaperFolderError.photoNotFound(normalizedPath)
        }

        try saveTahoePlist(plist)
    }

    /// List the individual image files registered in "Your Photos".
    public func listPhotos() throws -> [WallpaperFolder] {
        guard isTahoeOrLater else { return [] }
        let plist = try loadTahoePlist()
        return plist.choiceRequestsImageFiles.compactMap { entryData in
            guard let path = pathFromEntryData(entryData) else { return nil }
            return WallpaperFolder(path: path)
        }
    }

    /// Counts of each kind of source that contributes to the "Your Photos" area.
    public struct YourPhotosContents {
        public let imageFiles: Int
        public let imageFolders: Int
        public let assets: Int
        public let collections: Int
        public let people: Int

        public var total: Int { imageFiles + imageFolders + assets + collections + people }
    }

    /// Inspect what is currently populating the "Your Photos" area.
    public func yourPhotosContents() throws -> YourPhotosContents {
        let plist = try loadTahoePlist()
        return YourPhotosContents(
            imageFiles: plist.choiceRequestsImageFiles.count,
            imageFolders: plist.choiceRequestsImageFolders.count,
            assets: plist.choiceRequestsAssets.count,
            collections: plist.choiceRequestsCollectionIdentifiers.count,
            people: plist.choiceRequestsPersonIdentifiers.count
        )
    }

    /// Clear the "Your Photos" area. By default this clears individual images plus
    /// Photos-library sources (assets, albums, people). Pass `includeFolders: true`
    /// to also remove custom folders added with `addFolder`.
    /// Returns the contents that were present before clearing.
    @discardableResult
    public func resetYourPhotos(includeFolders: Bool = false) throws -> YourPhotosContents {
        guard isTahoeOrLater else {
            throw WallpaperFolderError.notSupportedOnThisOS("Resetting 'Your Photos' requires macOS 26 (Tahoe) or later")
        }

        var plist = try loadTahoePlist()
        let before = YourPhotosContents(
            imageFiles: plist.choiceRequestsImageFiles.count,
            imageFolders: plist.choiceRequestsImageFolders.count,
            assets: plist.choiceRequestsAssets.count,
            collections: plist.choiceRequestsCollectionIdentifiers.count,
            people: plist.choiceRequestsPersonIdentifiers.count
        )

        plist.choiceRequestsImageFiles = []
        plist.choiceRequestsAssets = []
        plist.choiceRequestsCollectionIdentifiers = []
        plist.choiceRequestsPersonIdentifiers = []
        if includeFolders {
            plist.choiceRequestsImageFolders = []
        }

        try saveTahoePlist(plist)
        return before
    }

    /// Add a photo and restart services in one call
    public func addPhotoAndApply(_ imagePath: String) throws {
        try addPhoto(imagePath)
        restartServices()
    }

    /// Remove a photo and restart services in one call
    public func removePhotoAndApply(_ imagePath: String) throws {
        try removePhoto(imagePath)
        restartServices()
    }

    /// Reset "Your Photos" and restart services in one call
    @discardableResult
    public func resetYourPhotosAndApply(includeFolders: Bool = false) throws -> YourPhotosContents {
        let before = try resetYourPhotos(includeFolders: includeFolders)
        restartServices()
        return before
    }

    /// Restart wallpaper-related services to apply changes
    public func restartServices() {
        if isTahoeOrLater {
            // Tahoe needs both cfprefsd and WallpaperAgent restarted
            killProcess("cfprefsd")
            killProcess("WallpaperAgent")
        } else {
            // Pre-Tahoe just needs cfprefsd
            killProcess("cfprefsd")
        }
    }
    
    /// Add folder and restart services in one call
    public func addFolderAndApply(_ folderPath: String) throws {
        try addFolder(folderPath)
        restartServices()
    }
    
    /// Remove folder and restart services in one call
    public func removeFolderAndApply(_ folderPath: String) throws {
        try removeFolder(folderPath)
        restartServices()
    }
    
    // MARK: - Legacy (Pre-Tahoe) Implementation
    
    private func addFolderLegacy(_ normalizedPath: String) throws {
        var folders = try readLegacyFolders()
        
        if folders.contains(where: { normalizePath($0) == normalizedPath }) {
            throw WallpaperFolderError.folderAlreadyExists(normalizedPath)
        }
        
        folders.append(normalizedPath)
        try writeLegacyFolders(folders)
    }
    
    private func removeFolderLegacy(_ normalizedPath: String) throws {
        var folders = try readLegacyFolders()
        
        let originalCount = folders.count
        folders.removeAll { normalizePath($0) == normalizedPath }
        
        guard folders.count < originalCount else {
            throw WallpaperFolderError.folderNotFound(normalizedPath)
        }
        
        try writeLegacyFolders(folders)
    }
    
    private func listFoldersLegacy() throws -> [WallpaperFolder] {
        let folders = try readLegacyFolders()
        return folders.map { WallpaperFolder(path: $0) }
    }
    
    /// Read UserFolderPaths from DSKDesktopPrefPane dictionary
    private func readLegacyFolders() throws -> [String] {
        // Use PlistBuddy to read the array directly
        let plistPath = "~/Library/Preferences/com.apple.systempreferences.plist"
        let expandedPath = (plistPath as NSString).expandingTildeInPath
        
        // First check if the key exists
        let checkTask = Process()
        checkTask.executableURL = URL(fileURLWithPath: "/usr/libexec/PlistBuddy")
        checkTask.arguments = ["-c", "Print :DSKDesktopPrefPane:UserFolderPaths", expandedPath]
        
        let pipe = Pipe()
        checkTask.standardOutput = pipe
        checkTask.standardError = FileHandle.nullDevice
        
        do {
            try checkTask.run()
            checkTask.waitUntilExit()
            
            guard checkTask.terminationStatus == 0 else {
                // Key doesn't exist
                return []
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }
            
            // Parse PlistBuddy array output
            // Format:
            // Array {
            //     /path/to/folder1
            //     /path/to/folder2
            // }
            return parsePlistBuddyArrayOutput(output)
        } catch {
            return []
        }
    }
    
    /// Parse the output of PlistBuddy Print for an array
    private func parsePlistBuddyArrayOutput(_ output: String) -> [String] {
        var results: [String] = []
        
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip "Array {" and "}" lines
            if trimmed.hasPrefix("Array") || trimmed == "}" || trimmed.isEmpty {
                continue
            }
            
            // Each path is on its own line, no quotes
            if !trimmed.isEmpty {
                results.append(trimmed)
            }
        }
        
        return results
    }
    
    /// Write UserFolderPaths to DSKDesktopPrefPane dictionary
    private func writeLegacyFolders(_ folders: [String]) throws {
        // Read existing DSKDesktopPrefPane dict first to preserve other keys
        var existingDict = readLegacyPrefPaneDict()
        
        if folders.isEmpty {
            existingDict.removeValue(forKey: "UserFolderPaths")
        } else {
            existingDict["UserFolderPaths"] = folders
        }
        
        // Write back the entire dictionary
        // We need to use PlistBuddy or write plist data for nested structures
        try writeLegacyPrefPaneDict(existingDict)
    }
    
    /// Read the DSKDesktopPrefPane dictionary as a Swift dictionary
    private func readLegacyPrefPaneDict() -> [String: Any] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["export", "com.apple.systempreferences", "-"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            
            guard task.terminationStatus == 0 else {
                return [:]
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let prefPane = plist["DSKDesktopPrefPane"] as? [String: Any] else {
                return [:]
            }
            
            return prefPane
        } catch {
            return [:]
        }
    }
    
    /// Write the DSKDesktopPrefPane dictionary using PlistBuddy
    private func writeLegacyPrefPaneDict(_ dict: [String: Any]) throws {
        let plistPath = "~/Library/Preferences/com.apple.systempreferences.plist"
        let expandedPath = (plistPath as NSString).expandingTildeInPath
        
        // Use PlistBuddy to set the nested dictionary
        // First, ensure DSKDesktopPrefPane exists
        let ensureTask = Process()
        ensureTask.executableURL = URL(fileURLWithPath: "/usr/libexec/PlistBuddy")
        ensureTask.arguments = ["-c", "Add :DSKDesktopPrefPane dict", expandedPath]
        ensureTask.standardOutput = FileHandle.nullDevice
        ensureTask.standardError = FileHandle.nullDevice
        try? ensureTask.run()
        ensureTask.waitUntilExit()
        
        // Delete existing UserFolderPaths if present
        let deleteTask = Process()
        deleteTask.executableURL = URL(fileURLWithPath: "/usr/libexec/PlistBuddy")
        deleteTask.arguments = ["-c", "Delete :DSKDesktopPrefPane:UserFolderPaths", expandedPath]
        deleteTask.standardOutput = FileHandle.nullDevice
        deleteTask.standardError = FileHandle.nullDevice
        try? deleteTask.run()
        deleteTask.waitUntilExit()
        
        // Add the array if we have folders
        if let folders = dict["UserFolderPaths"] as? [String], !folders.isEmpty {
            // Add empty array first
            let addArrayTask = Process()
            addArrayTask.executableURL = URL(fileURLWithPath: "/usr/libexec/PlistBuddy")
            addArrayTask.arguments = ["-c", "Add :DSKDesktopPrefPane:UserFolderPaths array", expandedPath]
            addArrayTask.standardOutput = FileHandle.nullDevice
            addArrayTask.standardError = FileHandle.nullDevice
            try addArrayTask.run()
            addArrayTask.waitUntilExit()
            
            // Add each folder
            for folder in folders {
                let addTask = Process()
                addTask.executableURL = URL(fileURLWithPath: "/usr/libexec/PlistBuddy")
                addTask.arguments = ["-c", "Add :DSKDesktopPrefPane:UserFolderPaths: string \(folder)", expandedPath]
                addTask.standardOutput = FileHandle.nullDevice
                addTask.standardError = FileHandle.nullDevice
                try addTask.run()
                addTask.waitUntilExit()
            }
        }
        
        // Sync preferences
        let syncTask = Process()
        syncTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        syncTask.arguments = ["cfprefsd"]
        syncTask.standardOutput = FileHandle.nullDevice
        syncTask.standardError = FileHandle.nullDevice
        try? syncTask.run()
        syncTask.waitUntilExit()
    }
    
    // MARK: - Tahoe+ Implementation
    
    private func addFolderTahoe(_ normalizedPath: String) throws {
        var plist = try loadTahoePlist()
        
        // Check for duplicates
        if try folderExistsTahoe(normalizedPath, in: plist) {
            throw WallpaperFolderError.folderAlreadyExists(normalizedPath)
        }
        
        let entryData = try createTahoeFolderEntry(for: normalizedPath)
        plist.choiceRequestsImageFolders.append(entryData)
        
        try saveTahoePlist(plist)
    }
    
    private func removeFolderTahoe(_ normalizedPath: String) throws {
        var plist = try loadTahoePlist()
        
        let originalCount = plist.choiceRequestsImageFolders.count
        
        plist.choiceRequestsImageFolders.removeAll { entryData in
            guard let entry = try? decodeTahoeEntry(from: entryData),
                  let existingPath = getPathFromTahoeEntry(entry) else {
                return false
            }
            return normalizePath(existingPath) == normalizedPath
        }
        
        guard plist.choiceRequestsImageFolders.count < originalCount else {
            throw WallpaperFolderError.folderNotFound(normalizedPath)
        }
        
        try saveTahoePlist(plist)
    }
    
    private func listFoldersTahoe() throws -> [WallpaperFolder] {
        let plist = try loadTahoePlist()
        
        return plist.choiceRequestsImageFolders.compactMap { entryData in
            guard let entry = try? decodeTahoeEntry(from: entryData),
                  let path = getPathFromTahoeEntry(entry) else {
                return nil
            }
            
            return WallpaperFolder(
                id: entry.id,
                path: path,
                dateAdded: entry.dateAdded
            )
        }
    }
    
    private func folderExistsTahoe(_ normalizedPath: String, in plist: TahoePlist) throws -> Bool {
        for entryData in plist.choiceRequestsImageFolders {
            if let entry = try? decodeTahoeEntry(from: entryData),
               let existingPath = getPathFromTahoeEntry(entry),
               normalizePath(existingPath) == normalizedPath {
                return true
            }
        }
        return false
    }
    
    private func createTahoeFolderEntry(for folderPath: String) throws -> Data {
        guard let cacheBasePath = cacheBasePath else {
            throw WallpaperFolderError.couldNotGetCacheDirectory
        }
        
        let entryID = UUID().uuidString.uppercased()
        let cloneID = UUID().uuidString.uppercased()
        
        // Ensure path ends with /
        var pathWithSlash = folderPath
        if !pathWithSlash.hasSuffix("/") {
            pathWithSlash += "/"
        }
        
        let folderURL = URL(fileURLWithPath: pathWithSlash, isDirectory: true)
        let originalURLString = folderURL.absoluteString
        let cloneURLString = "file://\(cacheBasePath)com.apple.wallpaper.extension.image/\(cloneID)/"
        
        // Create bookmark data
        let bookmarkData: Data
        do {
            bookmarkData = try folderURL.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw WallpaperFolderError.bookmarkCreationFailed(error.localizedDescription)
        }
        
        // Create entry with correct key order using NSDictionary
        // Key order matters for the binary plist: id, dateAdded, originalURL, originalURLBookmarkData, cloneURL
        let orderedDict = NSMutableDictionary()
        orderedDict["id"] = entryID
        orderedDict["dateAdded"] = Date()
        orderedDict["originalURL"] = ["relative": originalURLString]
        orderedDict["originalURLBookmarkData"] = bookmarkData
        orderedDict["cloneURL"] = ["relative": cloneURLString]
        
        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: orderedDict,
                format: .binary,
                options: 0
            )
            return data
        } catch {
            throw WallpaperFolderError.plistEncodingError(error.localizedDescription)
        }
    }
    
    private func photoExistsTahoe(_ normalizedPath: String, in plist: TahoePlist) throws -> Bool {
        for entryData in plist.choiceRequestsImageFiles {
            if let path = pathFromEntryData(entryData),
               normalizePath(path) == normalizedPath {
                return true
            }
        }
        return false
    }

    private func createTahoePhotoEntry(for filePath: String) throws -> Data {
        guard let cacheBasePath = cacheBasePath else {
            throw WallpaperFolderError.couldNotGetCacheDirectory
        }

        let copyID = UUID().uuidString.uppercased()

        let fileURL = URL(fileURLWithPath: filePath)
        let originalURLString = fileURL.absoluteString
        // The wallpaper agent copies the chosen image into its cache; mirror the
        // per-item cache layout used for folders (cloneURL) but point at the file.
        let encodedName = fileURL.lastPathComponent
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileURL.lastPathComponent
        let copyURLString = "file://\(cacheBasePath)com.apple.wallpaper.extension.image/\(copyID)/\(encodedName)"

        let bookmarkData: Data
        do {
            bookmarkData = try fileURL.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw WallpaperFolderError.bookmarkCreationFailed(error.localizedDescription)
        }

        // Mirrors the structure macOS writes for images dragged into "Your Photos":
        // dateAdded, originalURL, originalURLBookmarkData, copyURL, originatingBundle*
        let orderedDict = NSMutableDictionary()
        orderedDict["dateAdded"] = Date()
        orderedDict["originalURL"] = ["relative": originalURLString]
        orderedDict["originalURLBookmarkData"] = bookmarkData
        orderedDict["copyURL"] = ["relative": copyURLString]
        orderedDict["originatingBundleIdentifier"] = "com.github.bartreardon.WallpaperFolderManager"
        orderedDict["originatingBundleName"] = "WallpaperFolderManager"

        do {
            return try PropertyListSerialization.data(
                fromPropertyList: orderedDict,
                format: .binary,
                options: 0
            )
        } catch {
            throw WallpaperFolderError.plistEncodingError(error.localizedDescription)
        }
    }

    /// Extract the originalURL path from any entry blob (folder or image file).
    private func pathFromEntryData(_ data: Data) -> String? {
        guard let entry = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let original = entry["originalURL"] as? [String: Any],
              let relative = original["relative"] as? String,
              let url = URL(string: relative) else {
            return nil
        }
        return url.path.removingPercentEncoding ?? url.path
    }

    private func loadTahoePlist() throws -> TahoePlist {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            return TahoePlist()
        }
        
        let url = URL(fileURLWithPath: plistPath)
        let data = try Data(contentsOf: url)
        
        // Handle empty file
        guard !data.isEmpty else {
            return TahoePlist()
        }
        
        let decoder = PropertyListDecoder()
        do {
            return try decoder.decode(TahoePlist.self, from: data)
        } catch {
            // If decoding fails (e.g., plist has unexpected structure),
            // return empty plist rather than failing
            return TahoePlist()
        }
    }
    
    private func saveTahoePlist(_ plist: TahoePlist) throws {
        let url = URL(fileURLWithPath: plistPath)
        
        // Create directory if needed
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(plist)
        try data.write(to: url)
    }
    
    private func decodeTahoeEntry(from data: Data) throws -> TahoeEntry {
        let decoder = PropertyListDecoder()
        return try decoder.decode(TahoeEntry.self, from: data)
    }
    
    private func getPathFromTahoeEntry(_ entry: TahoeEntry) -> String? {
        guard let url = URL(string: entry.originalURL.relative) else { return nil }
        return url.path.removingPercentEncoding
    }
    
    // MARK: - Utility Methods
    
    private static func getCacheDirectory() throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/getconf")
        task.arguments = ["DARWIN_USER_CACHE_DIR"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        try task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard var path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            throw WallpaperFolderError.couldNotGetCacheDirectory
        }
        
        // Ensure /private prefix
        if path.hasPrefix("/var/") {
            path = "/private" + path
        }
        
        return path
    }
    
    private func normalizePath(_ path: String) -> String {
        var normalized = (path as NSString).expandingTildeInPath
        normalized = (normalized as NSString).standardizingPath
        // Remove trailing slash for comparison
        while normalized.hasSuffix("/") && normalized.count > 1 {
            normalized = String(normalized.dropLast())
        }
        return normalized
    }
    
    private func killProcess(_ name: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = [name]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }
}

// MARK: - Tahoe Plist Structures

private struct TahoePlist: Codable {
    var choiceRequestsAssets: [Data]
    var choiceRequestsCollectionIdentifiers: [Data]
    var choiceRequestsImageFiles: [Data]
    var choiceRequestsImageFolders: [Data]
    var choiceRequestsPersonIdentifiers: [Data]
    var didPerformImagesContainerMigration: Bool
    var didPerformPhotosContainerMigration: Bool
    var didPerformPhotosMigration: Bool

    enum CodingKeys: String, CodingKey {
        case choiceRequestsAssets = "ChoiceRequests.Assets"
        case choiceRequestsCollectionIdentifiers = "ChoiceRequests.CollectionIdentifiers"
        case choiceRequestsImageFiles = "ChoiceRequests.ImageFiles"
        case choiceRequestsImageFolders = "ChoiceRequests.ImageFolders"
        case choiceRequestsPersonIdentifiers = "ChoiceRequests.PersonIdentifiers"
        case didPerformImagesContainerMigration = "DidPerformImagesContainerMigration"
        case didPerformPhotosContainerMigration = "DidPerformPhotosContainerMigration"
        case didPerformPhotosMigration = "DidPerformPhotosMigration"
    }

    init() {
        choiceRequestsAssets = []
        choiceRequestsCollectionIdentifiers = []
        choiceRequestsImageFiles = []
        choiceRequestsImageFolders = []
        choiceRequestsPersonIdentifiers = []
        didPerformImagesContainerMigration = true
        didPerformPhotosContainerMigration = true
        didPerformPhotosMigration = true
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode with defaults for missing keys
        choiceRequestsAssets = try container.decodeIfPresent([Data].self, forKey: .choiceRequestsAssets) ?? []
        choiceRequestsCollectionIdentifiers = try container.decodeIfPresent([Data].self, forKey: .choiceRequestsCollectionIdentifiers) ?? []
        choiceRequestsImageFiles = try container.decodeIfPresent([Data].self, forKey: .choiceRequestsImageFiles) ?? []
        choiceRequestsImageFolders = try container.decodeIfPresent([Data].self, forKey: .choiceRequestsImageFolders) ?? []
        choiceRequestsPersonIdentifiers = try container.decodeIfPresent([Data].self, forKey: .choiceRequestsPersonIdentifiers) ?? []
        didPerformImagesContainerMigration = try container.decodeIfPresent(Bool.self, forKey: .didPerformImagesContainerMigration) ?? true
        didPerformPhotosContainerMigration = try container.decodeIfPresent(Bool.self, forKey: .didPerformPhotosContainerMigration) ?? true
        didPerformPhotosMigration = try container.decodeIfPresent(Bool.self, forKey: .didPerformPhotosMigration) ?? true
    }
}

private struct TahoeEntry: Codable {
    let id: String
    let dateAdded: Date
    let originalURL: RelativeURL
    let originalURLBookmarkData: Data
    let cloneURL: RelativeURL
    
    struct RelativeURL: Codable {
        let relative: String
    }
}
