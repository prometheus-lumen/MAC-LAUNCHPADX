//
//  LaunchpadXUITests.swift
//  LaunchpadXUITests
//
//  Created by 张航 on 2026/7/29.
//

import AppKit
import XCTest

final class LaunchpadXUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testLongPressEntersEditingAndBackgroundTapExits() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--show-launcher-for-ui-testing",
            "--ui-testing-isolated-data",
            "--ui-testing-fixtures",
        ]
        app.launch()
        app.activate()

        let root = app.descendants(matching: .any)
            .matching(identifier: "launcher.root")
            .firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 8))
        let launcherPanel = app.dialogs.firstMatch
        XCTAssertTrue(launcherPanel.exists)
        let visibleTile = app.buttons["Fixture 0"].firstMatch
        XCTAssertTrue(visibleTile.waitForExistence(timeout: 8))

        visibleTile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.25)
        XCTAssertEqual(root.value as? String, "editing")

        let adjacentTile = app.buttons["Fixture 1"].firstMatch
        XCTAssertTrue(adjacentTile.exists)
        let panelFrame = launcherPanel.frame
        let blankPointBetweenTiles = launcherPanel.coordinate(
            withNormalizedOffset: CGVector(
                dx: (
                    (visibleTile.frame.maxX + adjacentTile.frame.minX) / 2
                        - panelFrame.minX
                ) / panelFrame.width,
                dy: (visibleTile.frame.midY - panelFrame.minY) / panelFrame.height
            )
        )
        blankPointBetweenTiles.tap()
        XCTAssertEqual(root.value as? String, "normal")
        XCTAssertEqual(visibleTile.value as? String, "normal")
        Thread.sleep(forTimeInterval: 0.50)
        let stoppedFrame = visibleTile.frame
        Thread.sleep(forTimeInterval: 0.35)
        XCTAssertEqual(visibleTile.value as? String, "normal")
        let stableFrame = visibleTile.frame
        XCTAssertEqual(stoppedFrame.midX, stableFrame.midX, accuracy: 0.1)
        XCTAssertEqual(stoppedFrame.midY, stableFrame.midY, accuracy: 0.1)
        XCTAssertEqual(stoppedFrame.width, stableFrame.width, accuracy: 0.1)
        XCTAssertEqual(stoppedFrame.height, stableFrame.height, accuracy: 0.1)
    }

    @MainActor
    func testFolderRenameAndBackgroundTapExitsEditing() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--show-launcher-for-ui-testing",
            "--ui-testing-isolated-data",
            "--ui-testing-fixtures",
            "--ui-testing-existing-folder",
        ]
        app.launch()
        app.activate()

        let root = app.descendants(matching: .any)
            .matching(identifier: "launcher.root")
            .firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 8))
        let launcherPanel = app.dialogs.firstMatch
        let editSource = app.buttons["Fixture 0"].firstMatch
        let folder = app.buttons["Fixture Folder"].firstMatch
        let rightNeighbor = app.buttons["Fixture 3"].firstMatch
        XCTAssertTrue(editSource.waitForExistence(timeout: 8))
        XCTAssertTrue(folder.exists)
        XCTAssertTrue(rightNeighbor.exists)
        let panelFrame = launcherPanel.frame
        let folderCoordinate = launcherPanel.coordinate(
            withNormalizedOffset: CGVector(
                dx: ((editSource.frame.midX + rightNeighbor.frame.midX) / 2 - panelFrame.minX)
                    / panelFrame.width,
                dy: (editSource.frame.midY - panelFrame.minY) / panelFrame.height
            )
        )

        editSource.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.25)
        XCTAssertEqual(root.value as? String, "editing")

        folderCoordinate.click()
        let folderName = app.staticTexts["Fixture Folder"].firstMatch
        XCTAssertTrue(folderName.waitForExistence(timeout: 3))
        folderName.doubleClick()

        let editor = app.textFields
            .matching(NSPredicate(format: "placeholderValue == %@", "Folder name"))
            .firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(editor.exists)
        XCTAssertTrue(app.buttons["Fixture Folder"].firstMatch.exists)

        XCTAssertTrue(launcherPanel.exists)
        launcherPanel.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.50))
            .tap()
        XCTAssertEqual(root.value as? String, "normal")
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: "folder.tile")
            .firstMatch.exists)
    }

    @MainActor
    func testDraggingToRightEdgeMovesApplicationOnlyToNextPage() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--show-launcher-for-ui-testing",
            "--ui-testing-isolated-data",
            "--ui-testing-fixtures",
            "--ui-testing-many-fixtures",
        ]
        app.launch()
        app.activate()

        let root = app.descendants(matching: .any)
            .matching(identifier: "launcher.root")
            .firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 8))
        let launcherFrame = NSScreen.main?.frame ?? app.dialogs.firstMatch.frame
        let source = app.buttons["Fixture 0"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 8))
        let coordinateSpace = app.textFields.firstMatch
        XCTAssertTrue(coordinateSpace.exists)
        let coordinateFrame = coordinateSpace.frame
        let sourceCenter = source.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        let rightEdge = coordinateSpace.coordinate(
            withNormalizedOffset:
            CGVector(
                dx: (launcherFrame.maxX - 72 - coordinateFrame.minX) / coordinateFrame.width,
                dy: (launcherFrame.midY - coordinateFrame.minY) / coordinateFrame.height
            )
        )

        sourceCenter.press(
                forDuration: 1.25,
                thenDragTo: rightEdge,
                withVelocity: .slow,
                thenHoldForDuration: 1.0
            )

        XCTAssertEqual(root.value as? String, "editing")
        XCTAssertTrue(app.buttons["Fixture 35"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Fixture 0"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["Fixture 1"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Fixture 70"].firstMatch.exists)
    }

    @MainActor
    func testDraggingToLeftEdgeMovesApplicationOnlyToPreviousPage() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--show-launcher-for-ui-testing",
            "--ui-testing-isolated-data",
            "--ui-testing-fixtures",
            "--ui-testing-many-fixtures",
        ]
        app.launch()
        app.activate()

        let root = app.descendants(matching: .any)
            .matching(identifier: "launcher.root")
            .firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 8))
        app.typeKey(.rightArrow, modifierFlags: [])
        let launcherFrame = NSScreen.main?.frame ?? app.dialogs.firstMatch.frame
        let source = app.buttons["Fixture 35"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 4))
        let coordinateSpace = app.textFields.firstMatch
        XCTAssertTrue(coordinateSpace.exists)
        let coordinateFrame = coordinateSpace.frame
        let sourceCenter = source.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        let leftEdge = coordinateSpace.coordinate(
            withNormalizedOffset:
            CGVector(
                dx: (launcherFrame.minX + 72 - coordinateFrame.minX) / coordinateFrame.width,
                dy: (launcherFrame.midY - coordinateFrame.minY) / coordinateFrame.height
            )
        )

        sourceCenter.press(
                forDuration: 1.25,
                thenDragTo: leftEdge,
                withVelocity: .slow,
                thenHoldForDuration: 1.0
            )

        XCTAssertEqual(root.value as? String, "editing")
        XCTAssertTrue(app.buttons["Fixture 0"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Fixture 35"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["Fixture 34"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Fixture 70"].firstMatch.exists)
    }

    @MainActor
    func testDraggedApplicationStaysAtItsNewPosition() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--show-launcher-for-ui-testing",
            "--ui-testing-isolated-data",
            "--ui-testing-fixtures",
            "--ui-testing-many-fixtures",
        ]
        app.launch()
        app.activate()

        let root = app.descendants(matching: .any)
            .matching(identifier: "launcher.root")
            .firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 8))
        let launcherPanel = app.dialogs.firstMatch
        XCTAssertTrue(launcherPanel.exists)

        let source = app.buttons["Fixture 0"].firstMatch
        let target = app.buttons["Fixture 3"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 8))
        XCTAssertTrue(target.exists)
        let originalFrame = source.frame
        let targetOriginalFrame = target.frame
        let panelFrame = launcherPanel.frame
        let targetOriginalCoordinate = launcherPanel.coordinate(
            withNormalizedOffset: CGVector(
                dx: (targetOriginalFrame.minX + 5 - panelFrame.minX) / panelFrame.width,
                dy: (targetOriginalFrame.midY - panelFrame.minY) / panelFrame.height
            )
        )

        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 1.25,
                thenDragTo: targetOriginalCoordinate,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
        XCTAssertEqual(root.value as? String, "editing")

        let moved = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                source.exists
                    && source.frame != originalFrame
                    && abs(source.frame.midX - targetOriginalFrame.midX) < 2
                    && abs(source.frame.midY - targetOriginalFrame.midY) < 2
            },
            object: nil
        )
        let result = XCTWaiter.wait(for: [moved], timeout: 3)
        if result != .completed {
            let currentSourceFrame = source.exists ? source.frame : .null
            let currentTargetFrame = target.exists ? target.frame : .null
            XCTFail(
                "source: \(currentSourceFrame), original: \(originalFrame), "
                    + "target slot: \(targetOriginalFrame), target now: \(currentTargetFrame)"
            )
        }
    }

    @MainActor
    func testDraggedApplicationCanBeAddedToExistingFolder() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--show-launcher-for-ui-testing",
            "--ui-testing-isolated-data",
            "--ui-testing-fixtures",
            "--ui-testing-existing-folder",
        ]
        app.launch()
        app.activate()

        let root = app.descendants(matching: .any)
            .matching(identifier: "launcher.root")
            .firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 8))
        let launcherPanel = app.dialogs.firstMatch
        let source = app.buttons["Fixture 7"].firstMatch
        let folder = app.buttons["Fixture Folder"].firstMatch
        let leftNeighbor = app.buttons["Fixture 0"].firstMatch
        let rightNeighbor = app.buttons["Fixture 3"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 8))
        XCTAssertTrue(folder.exists)
        XCTAssertTrue(leftNeighbor.exists)
        XCTAssertTrue(rightNeighbor.exists)
        let panelFrame = launcherPanel.frame
        let folderIconCoordinate = launcherPanel.coordinate(
            withNormalizedOffset: CGVector(
                dx: ((leftNeighbor.frame.midX + rightNeighbor.frame.midX) / 2 - panelFrame.minX)
                    / panelFrame.width,
                dy: (leftNeighbor.frame.midY - panelFrame.minY) / panelFrame.height
            )
        )

        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.25)
        XCTAssertEqual(root.value as? String, "editing")
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.35,
                thenDragTo: folderIconCoordinate,
                withVelocity: .slow,
                thenHoldForDuration: 0.7
            )

        let removedFromRoot = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: source
        )
        XCTAssertEqual(XCTWaiter.wait(for: [removedFromRoot], timeout: 3), .completed)

        launcherPanel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
        XCTAssertEqual(root.value as? String, "normal")
        folderIconCoordinate.click()
        let applicationInsideFolder = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier == %@ AND label == %@",
                    "folder.tile",
                    "Fixture 7"
                )
            )
            .firstMatch
        XCTAssertTrue(applicationInsideFolder.waitForExistence(timeout: 3))
    }

    @MainActor
    func testFolderOpensWhileEditingAndApplicationCanBeDraggedOut() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--show-launcher-for-ui-testing",
            "--ui-testing-isolated-data",
            "--ui-testing-fixtures",
            "--ui-testing-existing-folder",
        ]
        app.launch()
        app.activate()

        let root = app.descendants(matching: .any)
            .matching(identifier: "launcher.root")
            .firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 8))
        let launcherPanel = app.dialogs.firstMatch
        let editSource = app.buttons["Fixture 0"].firstMatch
        let leftNeighbor = editSource
        let rightNeighbor = app.buttons["Fixture 3"].firstMatch
        XCTAssertTrue(editSource.waitForExistence(timeout: 8))
        XCTAssertTrue(rightNeighbor.exists)
        let panelFrame = launcherPanel.frame
        let folderCoordinate = launcherPanel.coordinate(
            withNormalizedOffset: CGVector(
                dx: ((leftNeighbor.frame.midX + rightNeighbor.frame.midX) / 2 - panelFrame.minX)
                    / panelFrame.width,
                dy: (leftNeighbor.frame.midY - panelFrame.minY) / panelFrame.height
            )
        )

        editSource.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.25)
        XCTAssertEqual(root.value as? String, "editing")
        folderCoordinate.click()

        let folderChild = app.descendants(matching: .any)
            .matching(identifier: "folder.tile")
            .firstMatch
        XCTAssertTrue(folderChild.waitForExistence(timeout: 3))
        let outsideFolder = launcherPanel.coordinate(
            withNormalizedOffset: CGVector(dx: 0.10, dy: 0.52)
        )
        folderChild.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.35,
                thenDragTo: outsideFolder,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )

        XCTAssertFalse(folderChild.exists)
        XCTAssertEqual(root.value as? String, "editing")
        XCTAssertTrue(app.buttons["Fixture 1"].firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testApplicationsInsideFolderCanBeReorderedWhileEditing() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--show-launcher-for-ui-testing",
            "--ui-testing-isolated-data",
            "--ui-testing-fixtures",
            "--ui-testing-existing-folder",
        ]
        app.launch()
        app.activate()

        let root = app.descendants(matching: .any)
            .matching(identifier: "launcher.root")
            .firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 8))
        let launcherPanel = app.dialogs.firstMatch
        let editSource = app.buttons["Fixture 0"].firstMatch
        let rightNeighbor = app.buttons["Fixture 3"].firstMatch
        XCTAssertTrue(editSource.waitForExistence(timeout: 8))
        XCTAssertTrue(rightNeighbor.exists)
        let panelFrame = launcherPanel.frame
        let folderCoordinate = launcherPanel.coordinate(
            withNormalizedOffset: CGVector(
                dx: ((editSource.frame.midX + rightNeighbor.frame.midX) / 2 - panelFrame.minX)
                    / panelFrame.width,
                dy: (editSource.frame.midY - panelFrame.minY) / panelFrame.height
            )
        )

        editSource.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.25)
        XCTAssertEqual(root.value as? String, "editing")
        folderCoordinate.click()

        let folderTiles = app.images.matching(identifier: "folder.tile")
        XCTAssertEqual(folderTiles.count, 2)
        let first = folderTiles.matching(
            NSPredicate(format: "label == %@", "Fixture 1")
        ).firstMatch
        let second = folderTiles.matching(
            NSPredicate(format: "label == %@", "Fixture 2")
        ).firstMatch
        XCTAssertTrue(first.exists)
        XCTAssertTrue(second.exists)
        let firstOriginalFrame = first.frame
        let secondOriginalFrame = second.frame
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.35,
                thenDragTo: second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )

        let reordered = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                first.exists
                    && abs(first.frame.midX - secondOriginalFrame.midX) < 3
                    && abs(second.frame.midX - firstOriginalFrame.midX) < 3
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 3), .completed)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
