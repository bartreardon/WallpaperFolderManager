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
    case folderAlreadyExists(String)
    case folderNotFound(String)
    case plistEncodingError(String)
    case plistReadError(String)
    case bookmarkCreationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .couldNotGetCacheDirectory:
            return "Could not determine user cache directory"
        case .notADirectory(let path):
            return "'\(path)' is not a valid directory"
        case .folderAlreadyExists(let path):
            return "Folder '\(path)' is already registered"
        case .folderNotFound(let path):
            return "Folder '\(path)' not found in registered folders"
        case .plistEncodingError(let details):
            return "Failed to encode plist: \(details)"
        case .plistReadError(let details):
            return "Failed to read plist: \(details)"
        case .bookmarkCreationFailed(let details):
            return "Failed to create bookmark: \(details)"
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
        var plist = try loadLegacyPlist()
        var folders = plist["UserFolderPaths"] as? [String] ?? []
        
        if folders.contains(where: { normalizePath($0) == normalizedPath }) {
            throw WallpaperFolderError.folderAlreadyExists(normalizedPath)
        }
        
        folders.append(normalizedPath)
        plist["UserFolderPaths"] = folders
        
        try saveLegacyPlist(plist)
    }
    
    private func removeFolderLegacy(_ normalizedPath: String) throws {
        var plist = try loadLegacyPlist()
        var folders = plist["UserFolderPaths"] as? [String] ?? []
        
        let originalCount = folders.count
        folders.removeAll { normalizePath($0) == normalizedPath }
        
        guard folders.count < originalCount else {
            throw WallpaperFolderError.folderNotFound(normalizedPath)
        }
        
        plist["UserFolderPaths"] = folders
        try saveLegacyPlist(plist)
    }
    
    private func listFoldersLegacy() throws -> [WallpaperFolder] {
        let plist = try loadLegacyPlist()
        let folders = plist["UserFolderPaths"] as? [String] ?? []
        
        return folders.map { WallpaperFolder(path: $0) }
    }
    
    private func loadLegacyPlist() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            return [:]
        }
        
        let url = URL(fileURLWithPath: plistPath)
        let data = try Data(contentsOf: url)
        
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw WallpaperFolderError.plistReadError("Could not parse plist as dictionary")
        }
        
        return plist
    }
    
    private func saveLegacyPlist(_ plist: [String: Any]) throws {
        let url = URL(fileURLWithPath: plistPath)
        
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .binary,
            options: 0
        )
        
        try data.write(to: url)
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
    var choiceRequestsImageFolders: [Data]
    var choiceRequestsPersonIdentifiers: [Data]
    var didPerformPhotosMigration: Bool
    
    enum CodingKeys: String, CodingKey {
        case choiceRequestsAssets = "ChoiceRequests.Assets"
        case choiceRequestsCollectionIdentifiers = "ChoiceRequests.CollectionIdentifiers"
        case choiceRequestsImageFolders = "ChoiceRequests.ImageFolders"
        case choiceRequestsPersonIdentifiers = "ChoiceRequests.PersonIdentifiers"
        case didPerformPhotosMigration = "DidPerformPhotosMigration"
    }
    
    init() {
        choiceRequestsAssets = []
        choiceRequestsCollectionIdentifiers = []
        choiceRequestsImageFolders = []
        choiceRequestsPersonIdentifiers = []
        didPerformPhotosMigration = true
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode with defaults for missing keys
        choiceRequestsAssets = try container.decodeIfPresent([Data].self, forKey: .choiceRequestsAssets) ?? []
        choiceRequestsCollectionIdentifiers = try container.decodeIfPresent([Data].self, forKey: .choiceRequestsCollectionIdentifiers) ?? []
        choiceRequestsImageFolders = try container.decodeIfPresent([Data].self, forKey: .choiceRequestsImageFolders) ?? []
        choiceRequestsPersonIdentifiers = try container.decodeIfPresent([Data].self, forKey: .choiceRequestsPersonIdentifiers) ?? []
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
