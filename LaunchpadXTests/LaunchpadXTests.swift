//
//  LaunchpadXTests.swift
//  LaunchpadXTests
//
//  Created by 张航 on 2026/7/29.
//

import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import LaunchpadX

struct LaunchpadXTests {
    @MainActor
    @Test func editingLongPressDurationIsExactlyOneSecond() {
        #expect(LaunchpadTheme.editingLongPressDuration == 1.0)
    }

    @MainActor
    @Test func searchPrioritizesExactNameAndMatchesBundleID() {
        let calculator = makeRecord(name: "Calculator", bundleID: "com.apple.calculator")
        let calendar = makeRecord(name: "Calendar", bundleID: "com.apple.calendar")
        let index = SearchIndex()

        let exact = index.search(query: "Calculator", records: [calculator, calendar], sort: .relevance)
        #expect(exact.first?.application.displayName == "Calculator")

        let bundle = index.search(query: "apple.calendar", records: [calculator, calendar], sort: .relevance)
        #expect(bundle.first?.application.displayName == "Calendar")
    }

    @MainActor
    @Test func searchRecognizesChinesePinyinInitials() {
        let music = makeRecord(name: "网易云音乐", bundleID: "com.example.music")
        let results = SearchIndex().search(query: "wyyy", records: [music], sort: .relevance)
        #expect(results.count == 1)
    }

    @MainActor
    @Test func chineseSearchExcludesUsageOnlyMatches() {
        let wechat = makeRecord(name: "微信", bundleID: "com.tencent.xinWeChat")
        let developerTools = makeRecord(name: "微信开发者工具", bundleID: "com.tencent.wechat.devtools")
        let enterpriseWechat = makeRecord(name: "企业微信", bundleID: "com.tencent.WeWorkMac")
        let dictionary = makeRecord(name: "词典", bundleID: "com.apple.Dictionary", launchCount: 80)
        let diskUtility = makeRecord(name: "磁盘工具", bundleID: "com.apple.DiskUtility", launchCount: 70)
        let bluetooth = makeRecord(name: "蓝牙文件交换", bundleID: "com.apple.BluetoothFileExchange", launchCount: 60)

        let results = SearchIndex().search(
            query: "微信",
            records: [dictionary, diskUtility, bluetooth, enterpriseWechat, developerTools, wechat],
            sort: .relevance
        )

        #expect(results.map(\.application.displayName) == ["微信", "微信开发者工具", "企业微信"])
    }

    @MainActor
    @Test func usageOnlyBreaksTiesBetweenTextualMatches() {
        let exact = makeRecord(name: "微信", bundleID: "com.tencent.xinWeChat")
        let unrelated = makeRecord(name: "词典", bundleID: "com.apple.Dictionary", launchCount: 1_000)
        let results = SearchIndex().search(query: "微信", records: [unrelated, exact], sort: .relevance)

        #expect(results.map(\.application.displayName) == ["微信"])
    }

    @MainActor
    @Test func trackpadClassifierMapsPhysicalLeftSwipeToNextPage() {
        var classifier = TrackpadGestureClassifier()
        #expect(classifier.consume(horizontal: 23, vertical: 0) == nil)
        #expect(classifier.consume(horizontal: 24, vertical: 0) == .nextPage)
        #expect(classifier.consume(horizontal: 200, vertical: 0) == nil)
        classifier.reset()
        #expect(classifier.consume(horizontal: -47, vertical: 0) == .previousPage)
        classifier.reset()
        #expect(classifier.consume(horizontal: 0, vertical: -47) == .dismiss)
    }

    @MainActor
    @Test func trackpadClassifierSupportsReversedPageDirection() {
        var classifier = TrackpadGestureClassifier()
        #expect(classifier.consume(horizontal: 47, vertical: 0, reversesPageDirection: true) == .previousPage)
        classifier.reset()
        #expect(classifier.consume(horizontal: -47, vertical: 0, reversesPageDirection: true) == .nextPage)
    }

    @MainActor
    @Test func reversedPageDirectionSettingPersists() {
        let suiteName = "LaunchpadXTests.pageDirection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = SettingsStore(defaults: defaults)
        #expect(initial.reversePageDirection == false)
        initial.reversePageDirection = true
        #expect(SettingsStore(defaults: defaults).reversePageDirection == true)
    }

    @MainActor
    @Test func shortTextDoesNotMatchAppleBundleIdentifier() {
        let bluetoothFileExchange = makeRecord(name: "Bluetooth File Exchange", bundleID: "com.apple.BluetoothFileExchange")
        let results = SearchIndex().search(query: "app", records: [bluetoothFileExchange], sort: .relevance)
        #expect(results.isEmpty)
    }

    @MainActor
    @Test func droppingOneRootApplicationOnAnotherCreatesFolderAtTargetPosition() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ApplicationRecord.self,
            LayoutItemRecord.self,
            configurations: configuration
        )
        let repository = LayoutRepository(container: container)
        let first = InstalledApplication(
            bundleIdentifier: "com.example.first",
            displayName: "First",
            bundleURL: URL(fileURLWithPath: "/Applications/First.app")
        )
        let second = InstalledApplication(
            bundleIdentifier: "com.example.second",
            displayName: "Second",
            bundleURL: URL(fileURLWithPath: "/Applications/Second.app")
        )
        let third = InstalledApplication(
            bundleIdentifier: "com.example.third",
            displayName: "Third",
            bundleURL: URL(fileURLWithPath: "/Applications/Third.app")
        )

        let applications = [first, second, third]
        try repository.reconcile(discovered: applications)
        let before = try repository.snapshot(discoveredApplications: applications)
        let folderID = try repository.createFolder(
            draggedEntryID: before.entries[2].id,
            targetEntryID: before.entries[1].id
        )
        let after = try repository.snapshot(discoveredApplications: applications)

        #expect(after.entries.count == 2)
        #expect(after.entries[1].id == folderID)
        #expect(after.entries[1].kind == .folder)
        #expect(after.entries[1].childApplicationRecordIDs.count == 2)
    }

    @MainActor
    @Test func droppingRootApplicationIntoExistingFolderKeepsFolderPosition() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ApplicationRecord.self,
            LayoutItemRecord.self,
            configurations: configuration
        )
        let repository = LayoutRepository(container: container)
        let applications = (0..<4).map { index in
            InstalledApplication(
                bundleIdentifier: "com.example.folder.\(index)",
                displayName: "Application \(index)",
                bundleURL: URL(fileURLWithPath: "/Applications/Application \(index).app")
            )
        }

        try repository.reconcile(discovered: applications)
        let initial = try repository.snapshot(discoveredApplications: applications)
        let sourceRecordID = try #require(initial.entries[0].applicationRecordID)
        let createdFolderID = try repository.createFolder(
            draggedEntryID: initial.entries[2].id,
            targetEntryID: initial.entries[1].id
        )
        let folderID = try #require(createdFolderID)

        try repository.addRootApplication(initial.entries[0].id, toFolder: folderID)
        let after = try repository.snapshot(discoveredApplications: applications)

        #expect(after.entries.map(\.id) == [folderID, initial.entries[3].id])
        #expect(after.entries[0].childApplicationRecordIDs == [
            initial.entries[1].applicationRecordID,
            initial.entries[2].applicationRecordID,
            sourceRecordID,
        ])
    }

    @MainActor
    @Test func renamingFolderPersistsItsNewName() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ApplicationRecord.self,
            LayoutItemRecord.self,
            configurations: configuration
        )
        let repository = LayoutRepository(container: container)
        let applications = (0..<2).map { index in
            InstalledApplication(
                bundleIdentifier: "com.example.folder-rename.\(index)",
                displayName: "Rename \(index)",
                bundleURL: URL(fileURLWithPath: "/Applications/Rename \(index).app")
            )
        }

        try repository.reconcile(discovered: applications)
        let initial = try repository.snapshot(discoveredApplications: applications)
        let createdFolderID = try repository.createFolder(
            draggedEntryID: initial.entries[1].id,
            targetEntryID: initial.entries[0].id
        )
        let folderID = try #require(createdFolderID)

        try repository.renameFolder(id: folderID, name: "Renamed Folder")
        let renamed = try repository.snapshot(discoveredApplications: applications)

        #expect(renamed.entries.first?.title == "Renamed Folder")
    }

    @MainActor
    @Test func reorderingApplicationsInsideFolderPersistsExactOrder() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ApplicationRecord.self,
            LayoutItemRecord.self,
            configurations: configuration
        )
        let repository = LayoutRepository(container: container)
        let applications = (0..<4).map { index in
            InstalledApplication(
                bundleIdentifier: "com.example.folder-reorder.\(index)",
                displayName: "Folder Reorder \(index)",
                bundleURL: URL(fileURLWithPath: "/Applications/Folder Reorder \(index).app")
            )
        }
        try repository.reconcile(discovered: applications)
        let initial = try repository.snapshot(discoveredApplications: applications)
        let createdFolderID = try repository.createFolder(
            draggedEntryID: initial.entries[2].id,
            targetEntryID: initial.entries[1].id
        )
        let folderID = try #require(createdFolderID)
        try repository.addRootApplication(initial.entries[0].id, toFolder: folderID)
        let before = try repository.snapshot(discoveredApplications: applications)
        let requestedOrder = Array(before.entries[0].childApplicationRecordIDs.reversed())

        try repository.reorderFolderApplications(
            folderID: folderID,
            orderedRecordIDs: requestedOrder
        )
        let after = try repository.snapshot(discoveredApplications: applications)

        #expect(after.entries[0].childApplicationRecordIDs == requestedOrder)
    }

    @MainActor
    @Test func draggingApplicationOutOfFolderPlacesItBesideFolder() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ApplicationRecord.self,
            LayoutItemRecord.self,
            configurations: configuration
        )
        let repository = LayoutRepository(container: container)
        let applications = (0..<4).map { index in
            InstalledApplication(
                bundleIdentifier: "com.example.folder-extract.\(index)",
                displayName: "Folder Extract \(index)",
                bundleURL: URL(fileURLWithPath: "/Applications/Folder Extract \(index).app")
            )
        }
        try repository.reconcile(discovered: applications)
        let initial = try repository.snapshot(discoveredApplications: applications)
        let extractedEntryID = initial.entries[0].id
        let extractedRecordID = try #require(initial.entries[0].applicationRecordID)
        let trailingEntryID = initial.entries[3].id
        let createdFolderID = try repository.createFolder(
            draggedEntryID: initial.entries[2].id,
            targetEntryID: initial.entries[1].id
        )
        let folderID = try #require(createdFolderID)
        try repository.addRootApplication(extractedEntryID, toFolder: folderID)

        try repository.removeFromFolder(recordID: extractedRecordID)
        let after = try repository.snapshot(discoveredApplications: applications)

        #expect(after.entries.map(\.id) == [folderID, extractedEntryID, trailingEntryID])
        #expect(after.entries[0].childApplicationRecordIDs.count == 2)
    }

    @MainActor
    @Test func draggingOutOfTwoItemFolderDissolvesFolderAtSamePosition() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ApplicationRecord.self,
            LayoutItemRecord.self,
            configurations: configuration
        )
        let repository = LayoutRepository(container: container)
        let applications = (0..<3).map { index in
            InstalledApplication(
                bundleIdentifier: "com.example.folder-dissolve.\(index)",
                displayName: "Folder Dissolve \(index)",
                bundleURL: URL(fileURLWithPath: "/Applications/Folder Dissolve \(index).app")
            )
        }
        try repository.reconcile(discovered: applications)
        let initial = try repository.snapshot(discoveredApplications: applications)
        let remainingEntryID = initial.entries[1].id
        let extractedEntryID = initial.entries[2].id
        let extractedRecordID = try #require(initial.entries[2].applicationRecordID)
        _ = try repository.createFolder(
            draggedEntryID: extractedEntryID,
            targetEntryID: remainingEntryID
        )

        try repository.removeFromFolder(recordID: extractedRecordID)
        let after = try repository.snapshot(discoveredApplications: applications)

        #expect(after.entries.map(\.id) == [
            initial.entries[0].id,
            remainingEntryID,
            extractedEntryID,
        ])
        #expect(after.entries.allSatisfy { $0.kind == .application })
    }

    @MainActor
    @Test func folderDragOrderUsesTargetOriginalSlot() {
        let ids = (0..<5).map { _ in UUID() }

        #expect(LauncherViewModel.reorderedRecordIDs(
            moving: ids[1],
            toOriginalSlotOf: ids[3],
            in: ids
        ) == [ids[0], ids[2], ids[3], ids[1], ids[4]])
        #expect(LauncherViewModel.reorderedRecordIDs(
            moving: ids[4],
            toOriginalSlotOf: ids[1],
            in: ids
        ) == [ids[0], ids[4], ids[1], ids[2], ids[3]])
    }

    @MainActor
    @Test func liftingDraggedEntryCompactsGridWithoutLeavingPlaceholder() {
        let entries = (0..<4).map { _ in
            LauncherEntry(
                id: UUID(),
                kind: .application,
                applicationRecordID: UUID(),
                application: nil,
                folderName: nil,
                childApplicationRecordIDs: []
            )
        }
        let liftedID = entries[1].id
        let compacted = LauncherViewModel.compactedEntries(afterLifting: liftedID, from: entries)

        #expect(compacted.map(\.id) == [entries[0].id, entries[2].id, entries[3].id])
        #expect(!compacted.contains { $0.id == liftedID })
    }

    @MainActor
    @Test func dropCenterGroupsWhileDropEdgeReorders() {
        let iconSize = 94.0
        let center = CGPoint(x: (iconSize + 40) / 2, y: iconSize / 2)

        #expect(LauncherEntryDropDelegate.isGroupingLocation(center, iconSize: iconSize))
        #expect(!LauncherEntryDropDelegate.isGroupingLocation(CGPoint(x: 2, y: 2), iconSize: iconSize))
    }

    @MainActor
    @Test func dragPreviewReordersBeforeAndAfterTarget() {
        let entries = (0..<4).map { _ in
            LauncherEntry(
                id: UUID(),
                kind: .application,
                applicationRecordID: UUID(),
                application: nil,
                folderName: nil,
                childApplicationRecordIDs: []
            )
        }
        let before = LauncherViewModel.reorderedEntries(
            moving: entries[0].id,
            relativeTo: entries[2].id,
            insertAfter: false,
            in: entries
        )
        let after = LauncherViewModel.reorderedEntries(
            moving: entries[0].id,
            relativeTo: entries[2].id,
            insertAfter: true,
            in: entries
        )

        #expect(before.map(\.id) == [entries[1].id, entries[0].id, entries[2].id, entries[3].id])
        #expect(after.map(\.id) == [entries[1].id, entries[2].id, entries[0].id, entries[3].id])
    }

    @MainActor
    @Test func movingToAnotherApplicationOccupiesItsOriginalSlot() {
        let entries = (0..<5).map { _ in
            LauncherEntry(
                id: UUID(),
                kind: .application,
                applicationRecordID: UUID(),
                application: nil,
                folderName: nil,
                childApplicationRecordIDs: []
            )
        }

        let movingForward = LauncherViewModel.reorderedEntries(
            moving: entries[1].id,
            toOriginalSlotOf: entries[3].id,
            in: entries
        )
        let movingBackward = LauncherViewModel.reorderedEntries(
            moving: entries[4].id,
            toOriginalSlotOf: entries[1].id,
            in: entries
        )

        #expect(movingForward.map(\.id) == [
            entries[0].id,
            entries[2].id,
            entries[3].id,
            entries[1].id,
            entries[4].id,
        ])
        #expect(movingBackward.map(\.id) == [
            entries[0].id,
            entries[4].id,
            entries[1].id,
            entries[2].id,
            entries[3].id,
        ])
    }

    @MainActor
    @Test func droppingLiftedEntryOnBlankGridPersistsItAtEnd() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ApplicationRecord.self,
            LayoutItemRecord.self,
            configurations: configuration
        )
        let repository = LayoutRepository(container: container)
        let applications = (0..<3).map { index in
            InstalledApplication(
                bundleIdentifier: "com.example.move.\(index)",
                displayName: "Move \(index)",
                bundleURL: URL(fileURLWithPath: "/Applications/Move \(index).app")
            )
        }
        try repository.reconcile(discovered: applications)
        let before = try repository.snapshot(discoveredApplications: applications)
        let sourceID = before.entries[0].id
        let compactedPreview = LauncherViewModel.compactedEntries(
            afterLifting: sourceID,
            from: before.entries
        )
        let destinationID = LauncherViewModel.dropDestinationID(
            sourceID: sourceID,
            previewEntries: compactedPreview,
            fallbackDestinationID: nil
        )

        try repository.moveRootEntry(from: sourceID, before: destinationID)
        let after = try repository.snapshot(discoveredApplications: applications)

        #expect(after.entries.map(\.id) == [before.entries[1].id, before.entries[2].id, sourceID])
    }

    @MainActor
    @Test func droppingReorderedPreviewPersistsItsExactPosition() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ApplicationRecord.self,
            LayoutItemRecord.self,
            configurations: configuration
        )
        let repository = LayoutRepository(container: container)
        let applications = (0..<4).map { index in
            InstalledApplication(
                bundleIdentifier: "com.example.exact-move.\(index)",
                displayName: "Exact Move \(index)",
                bundleURL: URL(fileURLWithPath: "/Applications/Exact Move \(index).app")
            )
        }
        try repository.reconcile(discovered: applications)
        let before = try repository.snapshot(discoveredApplications: applications)
        let sourceID = before.entries[0].id
        let reorderedPreview = LauncherViewModel.reorderedEntries(
            moving: sourceID,
            relativeTo: before.entries[2].id,
            insertAfter: true,
            in: before.entries
        )
        let destinationID = LauncherViewModel.dropDestinationID(
            sourceID: sourceID,
            previewEntries: reorderedPreview,
            fallbackDestinationID: before.entries[2].id
        )

        try repository.moveRootEntry(from: sourceID, before: destinationID)
        let after = try repository.snapshot(discoveredApplications: applications)

        #expect(after.entries.map(\.id) == reorderedPreview.map(\.id))
    }

    @MainActor
    @Test func liftingLastApplicationOnPageDoesNotPullFromNextPage() {
        let entries = (0..<8).map { index in
            LauncherEntry(
                id: UUID(),
                kind: .application,
                applicationRecordID: UUID(),
                application: nil,
                folderName: nil,
                childApplicationRecordIDs: [],
                layoutIndex: index
            )
        }

        let compacted = LauncherViewModel.compactedEntries(
            afterLifting: entries[3].id,
            from: entries,
            capacity: 4
        )

        #expect(compacted.filter { $0.layoutIndex < 4 }.map(\.id) == [
            entries[0].id,
            entries[1].id,
            entries[2].id,
        ])
        #expect(compacted.first(where: { $0.id == entries[4].id })?.layoutIndex == 4)
    }

    @MainActor
    @Test func movingRootApplicationIntoFolderPreservesNextPageBoundary() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ApplicationRecord.self,
            LayoutItemRecord.self,
            configurations: configuration
        )
        let repository = LayoutRepository(container: container)
        let applications = (0..<6).map { index in
            InstalledApplication(
                bundleIdentifier: "com.example.page-boundary.\(index)",
                displayName: "Page Boundary \(index)",
                bundleURL: URL(fileURLWithPath: "/Applications/Page Boundary \(index).app")
            )
        }
        try repository.reconcile(discovered: applications)
        let before = try repository.snapshot(discoveredApplications: applications)
        _ = try repository.createFolder(
            draggedEntryID: before.entries[3].id,
            targetEntryID: before.entries[2].id
        )
        let after = try repository.snapshot(discoveredApplications: applications)

        #expect(after.entries.first(where: {
            $0.application?.displayName == "Page Boundary 4"
        })?.layoutIndex == 4)
        #expect(after.entries.filter { $0.layoutIndex < 4 }.count == 3)
    }

    @MainActor
    @Test func edgePageMovePlacesSourceOnAdjacentPageWithoutCrossPageBackfill() {
        let entries = (0..<8).map { index in
            LauncherEntry(
                id: UUID(),
                kind: .application,
                applicationRecordID: UUID(),
                application: nil,
                folderName: nil,
                childApplicationRecordIDs: [],
                layoutIndex: index
            )
        }

        let moved = LauncherViewModel.movedEntries(
            moving: entries[1].id,
            toPage: 1,
            in: entries,
            capacity: 4
        )
        let firstPageIDs = moved
            .filter { $0.layoutIndex < 4 }
            .sorted { $0.layoutIndex < $1.layoutIndex }
            .map(\.id)
        let secondPageIDs = moved
            .filter { $0.layoutIndex >= 4 && $0.layoutIndex < 8 }
            .sorted { $0.layoutIndex < $1.layoutIndex }
            .map(\.id)

        #expect(firstPageIDs == [entries[0].id, entries[2].id, entries[3].id, entries[7].id])
        #expect(secondPageIDs == [entries[4].id, entries[5].id, entries[6].id, entries[1].id])
    }

    @MainActor
    @Test func dragEdgeClassificationAndPageBoundsAreDeterministic() {
        let frame = CGRect(x: 100, y: 50, width: 1_000, height: 700)

        #expect(LauncherViewModel.dragPageDelta(
            screenX: 180,
            windowFrame: frame,
            threshold: 120
        ) == -1)
        #expect(LauncherViewModel.dragPageDelta(
            screenX: 1_020,
            windowFrame: frame,
            threshold: 120
        ) == 1)
        #expect(LauncherViewModel.dragPageDelta(
            screenX: 600,
            windowFrame: frame,
            threshold: 120
        ) == nil)
        #expect(LauncherViewModel.edgeDestinationPage(
            currentPage: 0,
            pageCount: 3,
            delta: -1
        ) == nil)
        #expect(LauncherViewModel.edgeDestinationPage(
            currentPage: 2,
            pageCount: 3,
            delta: 1
        ) == nil)
        #expect(LauncherViewModel.edgeDestinationPage(
            currentPage: 1,
            pageCount: 3,
            delta: -1
        ) == 0)
        #expect(LauncherViewModel.edgeDestinationPage(
            currentPage: 1,
            pageCount: 3,
            delta: 1
        ) == 2)
    }

    @MainActor
    private func makeRecord(
        name: String,
        bundleID: String,
        launchCount: Int = 0
    ) -> (ApplicationRecord, InstalledApplication) {
        let path = "/Applications/\(name).app"
        let record = ApplicationRecord(
            bundleIdentifier: bundleID,
            lastKnownPath: path,
            displayName: name,
            launchCount: launchCount
        )
        let app = InstalledApplication(bundleIdentifier: bundleID, displayName: name, bundleURL: URL(fileURLWithPath: path))
        return (record, app)
    }
}
