import Foundation
import SwiftData

@Model
final class ApplicationRecord {
    @Attribute(.unique) var id: UUID
    var bundleIdentifier: String?
    var lastKnownPath: String
    var displayName: String
    var alias: String?
    var isHidden: Bool
    var launchCount: Int
    var lastLaunchedAt: Date?
    var lastSeenAt: Date?
    var missingSince: Date?

    init(
        id: UUID = UUID(),
        bundleIdentifier: String? = nil,
        lastKnownPath: String,
        displayName: String,
        alias: String? = nil,
        isHidden: Bool = false,
        launchCount: Int = 0,
        lastLaunchedAt: Date? = nil,
        lastSeenAt: Date? = nil,
        missingSince: Date? = nil
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.lastKnownPath = lastKnownPath
        self.displayName = displayName
        self.alias = alias
        self.isHidden = isHidden
        self.launchCount = launchCount
        self.lastLaunchedAt = lastLaunchedAt
        self.lastSeenAt = lastSeenAt
        self.missingSince = missingSince
    }
}

@Model
final class LayoutItemRecord {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var applicationRecordID: UUID?
    var parentFolderID: UUID?
    var sortOrder: Int
    var folderName: String?

    init(
        id: UUID = UUID(),
        kind: LauncherEntryKind,
        applicationRecordID: UUID? = nil,
        parentFolderID: UUID? = nil,
        sortOrder: Int,
        folderName: String? = nil
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.applicationRecordID = applicationRecordID
        self.parentFolderID = parentFolderID
        self.sortOrder = sortOrder
        self.folderName = folderName
    }

    var kind: LauncherEntryKind {
        LauncherEntryKind(rawValue: kindRawValue) ?? .application
    }
}

enum LauncherSchemaV1 {
    static let schema = Schema([ApplicationRecord.self, LayoutItemRecord.self])
}
