import AppKit
import Carbon
import Foundation

struct InstalledApplication: Identifiable, Sendable, Hashable {
    let id: UUID
    let bundleIdentifier: String?
    let displayName: String
    let bundleURL: URL
    let version: String?
    let isSystemApplication: Bool

    nonisolated init(
        id: UUID = UUID(),
        bundleIdentifier: String?,
        displayName: String,
        bundleURL: URL,
        version: String? = nil,
        isSystemApplication: Bool = false
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.bundleURL = bundleURL
        self.version = version
        self.isSystemApplication = isSystemApplication
    }

    nonisolated var normalizedPath: String {
        bundleURL.standardizedFileURL.path.lowercased()
    }
}

enum LauncherEntryKind: String, Codable, Sendable {
    case application
    case folder
}

struct LauncherEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    var kind: LauncherEntryKind
    var applicationRecordID: UUID?
    var application: InstalledApplication?
    var folderName: String?
    var childApplicationRecordIDs: [UUID]
    var layoutIndex: Int = 0

    var title: String {
        switch kind {
        case .application:
            application?.displayName ?? "Missing Application"
        case .folder:
            folderName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Folder"
        }
    }
}

struct LauncherSnapshot: Sendable {
    var entries: [LauncherEntry]
    var applications: [UUID: InstalledApplication]
    var hiddenRecordIDs: Set<UUID>
}

enum SearchSortOrder: String, CaseIterable, Codable, Identifiable {
    case relevance
    case recent
    case name

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .relevance: String(localized: "Search sort relevance")
        case .recent: String(localized: "Search sort recent")
        case .name: String(localized: "Search sort name")
        }
    }
}

enum DisplayStrategy: String, CaseIterable, Codable, Identifiable {
    case cursor
    case primary
    case lastUsed
    case fixed

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .cursor: String(localized: "Display cursor")
        case .primary: String(localized: "Display primary")
        case .lastUsed: String(localized: "Display last used")
        case .fixed: String(localized: "Display fixed")
        }
    }
}

enum LauncherBackgroundKind: String, CaseIterable, Codable, Identifiable {
    case brandGradient
    case wallpaper
    case customImage

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .brandGradient: String(localized: "Background brand gradient")
        case .wallpaper: String(localized: "Background wallpaper")
        case .customImage: String(localized: "Background custom image")
        }
    }
}

struct HotKey: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let defaultLauncher = HotKey(keyCode: 49, carbonModifiers: UInt32(optionKey))
    static let defaultPreviousPage = HotKey(keyCode: 123, carbonModifiers: 0)
    static let defaultNextPage = HotKey(keyCode: 124, carbonModifiers: 0)

    var displayString: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        return parts.joined() + keyName
    }

    private var keyName: String {
        switch keyCode {
        case 49: "Space"
        case 36: "Return"
        case 53: "Esc"
        case 123: "←"
        case 124: "→"
        default: "Key \(keyCode)"
        }
    }

    func matches(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        self.keyCode == UInt32(keyCode) && carbonModifiers == Self.carbonModifiers(from: modifiers)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}

extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
