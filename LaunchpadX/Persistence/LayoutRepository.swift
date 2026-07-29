import Foundation
import SwiftData

@MainActor
final class LayoutRepository {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = true
    }

    func reconcile(discovered applications: [InstalledApplication], now: Date = .now) throws {
        let records = try fetchApplications()
        var unmatchedIDs = Set(records.map(\.id))
        var byPath = Dictionary(uniqueKeysWithValues: records.map { ($0.lastKnownPath.lowercased(), $0) })

        for app in applications {
            let normalizedPath = app.normalizedPath
            let matchingRecord: ApplicationRecord?

            if let pathRecord = byPath[normalizedPath] {
                matchingRecord = pathRecord
            } else if let bundleID = app.bundleIdentifier {
                let candidates = records.filter {
                    unmatchedIDs.contains($0.id) && $0.bundleIdentifier == bundleID
                }
                matchingRecord = candidates.count == 1 ? candidates[0] : nil
            } else {
                matchingRecord = nil
            }

            if let record = matchingRecord {
                record.bundleIdentifier = app.bundleIdentifier
                record.lastKnownPath = app.bundleURL.path
                record.displayName = app.displayName
                record.lastSeenAt = now
                record.missingSince = nil
                unmatchedIDs.remove(record.id)
                byPath[normalizedPath] = record
            } else {
                let record = ApplicationRecord(
                    bundleIdentifier: app.bundleIdentifier,
                    lastKnownPath: app.bundleURL.path,
                    displayName: app.displayName,
                    lastSeenAt: now
                )
                context.insert(record)
                try ensureRootLayout(for: record)
            }
        }

        for record in records where unmatchedIDs.contains(record.id) && record.missingSince == nil {
            record.missingSince = now
        }
        try context.save()
    }

    func snapshot(discoveredApplications applications: [InstalledApplication]) throws -> LauncherSnapshot {
        let records = try fetchApplications()
        let appsByPath = Dictionary(uniqueKeysWithValues: applications.map { ($0.normalizedPath, $0) })
        let applications = Dictionary(uniqueKeysWithValues: records.compactMap { record in
            appsByPath[record.lastKnownPath.lowercased()].map { (record.id, $0) }
        })
        let layout = try fetchLayout()
        let root = layout
            .filter { $0.parentFolderID == nil }
            .sorted { $0.sortOrder < $1.sortOrder }

        let entries = root.compactMap { item -> LauncherEntry? in
            switch item.kind {
            case .application:
                guard let recordID = item.applicationRecordID,
                      let record = records.first(where: { $0.id == recordID }),
                      !record.isHidden,
                      record.missingSince == nil,
                      let app = applications[recordID] else { return nil }
                return LauncherEntry(
                    id: item.id,
                    kind: .application,
                    applicationRecordID: recordID,
                    application: app,
                    folderName: nil,
                    childApplicationRecordIDs: [],
                    layoutIndex: item.sortOrder
                )
            case .folder:
                let children = layout
                    .filter { $0.parentFolderID == item.id }
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .compactMap(\.applicationRecordID)
                    .filter { applications[$0] != nil }
                guard !children.isEmpty else { return nil }
                return LauncherEntry(
                    id: item.id,
                    kind: .folder,
                    applicationRecordID: nil,
                    application: nil,
                    folderName: item.folderName,
                    childApplicationRecordIDs: children,
                    layoutIndex: item.sortOrder
                )
            }
        }
        let hidden = Set(records.filter(\.isHidden).map(\.id))
        return LauncherSnapshot(entries: entries, applications: applications, hiddenRecordIDs: hidden)
    }

    func visibleRecords(discoveredApplications applications: [InstalledApplication]) throws -> [(ApplicationRecord, InstalledApplication)] {
        let records = try fetchApplications()
        let apps = Dictionary(uniqueKeysWithValues: applications.map { ($0.normalizedPath, $0) })
        return records.compactMap { record in
            guard !record.isHidden, record.missingSince == nil,
                  let app = apps[record.lastKnownPath.lowercased()] else { return nil }
            return (record, app)
        }
    }

    func recordLaunched(recordID: UUID) throws {
        guard let record = try fetchApplications().first(where: { $0.id == recordID }) else { return }
        record.launchCount += 1
        record.lastLaunchedAt = .now
        try context.save()
    }

    func setHidden(_ hidden: Bool, recordID: UUID) throws {
        guard let record = try fetchApplications().first(where: { $0.id == recordID }) else { return }
        record.isHidden = hidden
        try context.save()
    }

    func setAlias(_ alias: String?, recordID: UUID) throws {
        guard let record = try fetchApplications().first(where: { $0.id == recordID }) else { return }
        record.alias = alias?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        try context.save()
    }

    func moveRootEntry(from source: UUID, before destination: UUID?) throws {
        var root = try fetchLayout().filter { $0.parentFolderID == nil }.sorted { $0.sortOrder < $1.sortOrder }
        guard let sourceIndex = root.firstIndex(where: { $0.id == source }) else { return }
        let item = root.remove(at: sourceIndex)
        let destinationIndex = destination.flatMap { id in root.firstIndex(where: { $0.id == id }) } ?? root.count
        root.insert(item, at: destinationIndex)
        normalize(root)
        try context.save()
    }

    func applyRootLayout(_ entries: [LauncherEntry]) throws {
        let root = try fetchLayout().filter { $0.parentFolderID == nil }
        let rootByID = Dictionary(uniqueKeysWithValues: root.map { ($0.id, $0) })
        let placements = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, max(0, $0.layoutIndex)) })
        guard placements.keys.allSatisfy({ rootByID[$0] != nil }),
              Set(placements.values).count == placements.count else { return }

        var occupied = Set<Int>()
        for (id, slot) in placements {
            rootByID[id]?.sortOrder = slot
            occupied.insert(slot)
        }

        for item in root
            .filter({ placements[$0.id] == nil })
            .sorted(by: { $0.sortOrder < $1.sortOrder }) {
            var slot = max(0, item.sortOrder)
            while occupied.contains(slot) { slot += 1 }
            item.sortOrder = slot
            occupied.insert(slot)
        }
        try context.save()
    }

    @discardableResult
    func createFolder(draggedEntryID: UUID, targetEntryID: UUID) throws -> UUID? {
        let layout = try fetchLayout()
        guard let dragged = layout.first(where: { $0.id == draggedEntryID }),
              let target = layout.first(where: { $0.id == targetEntryID }),
              dragged.kind == .application, target.kind == .application,
              dragged.parentFolderID == nil, target.parentFolderID == nil else { return nil }
        let folder = LayoutItemRecord(kind: .folder, sortOrder: target.sortOrder, folderName: String(localized: "New folder"))
        context.insert(folder)
        target.parentFolderID = folder.id
        target.sortOrder = 0
        dragged.parentFolderID = folder.id
        dragged.sortOrder = 1
        try context.save()
        return folder.id
    }

    func addRootApplication(_ applicationID: UUID, toFolder folderID: UUID) throws {
        let layout = try fetchLayout()
        guard let application = layout.first(where: { $0.id == applicationID }),
              let folder = layout.first(where: { $0.id == folderID }),
              application.kind == .application,
              application.parentFolderID == nil,
              folder.kind == .folder,
              folder.parentFolderID == nil else { return }

        let nextChildOrder = layout
            .filter { $0.parentFolderID == folderID }
            .map(\.sortOrder)
            .max()
            .map { $0 + 1 } ?? 0
        application.parentFolderID = folderID
        application.sortOrder = nextChildOrder
        try context.save()
    }

    func renameFolder(id: UUID, name: String) throws {
        guard let folder = try fetchLayout().first(where: { $0.id == id && $0.kind == .folder }) else { return }
        guard let nonEmptyName = name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else { return }
        folder.folderName = nonEmptyName
        try context.save()
    }

    func reorderFolderApplications(folderID: UUID, orderedRecordIDs: [UUID]) throws {
        let layout = try fetchLayout()
        guard layout.contains(where: { $0.id == folderID && $0.kind == .folder }) else { return }
        let children = layout
            .filter { $0.parentFolderID == folderID && $0.kind == .application }
        let childrenByRecordID = Dictionary(
            uniqueKeysWithValues: children.compactMap { child in
                child.applicationRecordID.map { ($0, child) }
            }
        )
        guard orderedRecordIDs.count == children.count,
              Set(orderedRecordIDs) == Set(childrenByRecordID.keys) else { return }
        normalize(orderedRecordIDs.compactMap { childrenByRecordID[$0] })
        try context.save()
    }

    func removeFromFolder(recordID: UUID) throws {
        let layout = try fetchLayout()
        guard let child = layout.first(where: { $0.applicationRecordID == recordID }), let folderID = child.parentFolderID,
              let folder = layout.first(where: { $0.id == folderID }) else { return }
        let root = layout.filter { $0.parentFolderID == nil && $0.id != folder.id }
        let folderSlot = folder.sortOrder
        let remaining = layout
            .filter { $0.parentFolderID == folderID && $0.id != child.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        child.parentFolderID = nil

        if remaining.count < 2 {
            if let remainingItem = remaining.first {
                makeRoom(in: root, at: folderSlot + 1)
                remainingItem.parentFolderID = nil
                remainingItem.sortOrder = folderSlot
                child.sortOrder = folderSlot + 1
            } else {
                child.sortOrder = folderSlot
            }
            context.delete(folder)
        } else {
            normalize(remaining)
            makeRoom(in: root + [folder], at: folderSlot + 1)
            child.sortOrder = folderSlot + 1
        }
        try context.save()
    }

    func resetLayout() throws {
        let layout = try fetchLayout()
        for item in layout { context.delete(item) }
        let records = try fetchApplications()
            .filter { $0.missingSince == nil }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        for (index, record) in records.enumerated() {
            context.insert(LayoutItemRecord(kind: .application, applicationRecordID: record.id, sortOrder: index))
        }
        try context.save()
    }

    func purgeMissing(olderThan date: Date) throws {
        let records = try fetchApplications().filter { ($0.missingSince ?? .distantFuture) < date }
        let ids = Set(records.map(\.id))
        for item in try fetchLayout() where ids.contains(item.applicationRecordID ?? UUID()) { context.delete(item) }
        for record in records { context.delete(record) }
        try context.save()
    }

    private func ensureRootLayout(for record: ApplicationRecord) throws {
        let layout = try fetchLayout()
        guard !layout.contains(where: { $0.applicationRecordID == record.id }) else { return }
        let nextOrder = (layout.filter { $0.parentFolderID == nil }.map(\.sortOrder).max() ?? -1) + 1
        context.insert(LayoutItemRecord(kind: .application, applicationRecordID: record.id, sortOrder: nextOrder))
    }

    private func fetchApplications() throws -> [ApplicationRecord] {
        try context.fetch(FetchDescriptor<ApplicationRecord>())
    }

    private func fetchLayout() throws -> [LayoutItemRecord] {
        try context.fetch(FetchDescriptor<LayoutItemRecord>())
    }

    private func normalize(_ items: [LayoutItemRecord]) {
        for (index, item) in items.enumerated() { item.sortOrder = index }
    }

    private func makeRoom(in items: [LayoutItemRecord], at requestedSlot: Int) {
        let itemsBySlot = Dictionary(uniqueKeysWithValues: items.map { ($0.sortOrder, $0) })
        var freeSlot = requestedSlot
        while itemsBySlot[freeSlot] != nil { freeSlot += 1 }
        guard freeSlot > requestedSlot else { return }
        for slot in stride(from: freeSlot - 1, through: requestedSlot, by: -1) {
            itemsBySlot[slot]?.sortOrder = slot + 1
        }
    }
}
