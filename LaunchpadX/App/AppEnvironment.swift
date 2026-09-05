import Foundation
import SwiftData

@MainActor
final class AppEnvironment {
    private enum ScanPolicy {
        static let initialDelay: Duration = .milliseconds(700)
        static let periodicInterval: Duration = .seconds(15 * 60)
    }

    let container: ModelContainer
    let repository: LayoutRepository
    let settings: SettingsStore
    let discovery: ApplicationDiscoveryService
    let launcher: ApplicationLauncherService
    let icons: IconProvider
    let searchIndex: SearchIndex
    let monitor: ApplicationMonitor
    let hotKeyManager: HotKeyManager
    let trackpadWakeService: TrackpadWakeService
    let loginItems: LoginItemManager
    let launcherViewModel: LauncherViewModel
    let launcherWindowController: LauncherWindowController
    lazy var settingsWindowController = SettingsWindowController(environment: self)
    private var scheduledScanTask: Task<Void, Never>?

    init() {
        do {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-isolated-data") {
                container = try ModelContainer(
                    for: LauncherSchemaV1.schema,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } else {
                container = try ModelContainer(for: LauncherSchemaV1.schema)
            }
#else
            container = try ModelContainer(for: LauncherSchemaV1.schema)
#endif
        } catch {
            fatalError("Unable to create LaunchpadX data store: \(error)")
        }
        repository = LayoutRepository(container: container)
        settings = SettingsStore()
        discovery = ApplicationDiscoveryService()
        launcher = ApplicationLauncherService()
        icons = IconProvider()
        searchIndex = SearchIndex()
        monitor = ApplicationMonitor()
        hotKeyManager = HotKeyManager()
        trackpadWakeService = TrackpadWakeService()
        loginItems = LoginItemManager()
        launcherViewModel = LauncherViewModel(
            repository: repository,
            settings: settings,
            discovery: discovery,
            launcher: launcher,
            icons: icons,
            searchIndex: searchIndex
        )
        launcherWindowController = LauncherWindowController(viewModel: launcherViewModel, settings: settings)

        monitor.onChange = { [weak launcherViewModel] in
            Task { @MainActor in await launcherViewModel?.rescan() }
        }
        hotKeyManager.onPressed = { [weak launcherWindowController] in
            DispatchQueue.main.async { launcherWindowController?.toggle() }
        }
        trackpadWakeService.onFiveFingerPinch = { [weak launcherWindowController] in
            launcherWindowController?.show()
        }
    }

    func start() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-fixtures") {
            let fixtureCount = ProcessInfo.processInfo.arguments.contains("--ui-testing-many-fixtures") ? 160 : 8
            let fixtures = (0..<fixtureCount).map { index in
                InstalledApplication(
                    bundleIdentifier: "com.launchpadx.ui-fixture.\(index)",
                    displayName: "Fixture \(index)",
                    bundleURL: URL(fileURLWithPath: "/Applications/Fixture \(index).app")
                )
            }
            launcherViewModel.loadForUITesting(fixtures)
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-existing-folder") {
                do {
                    let snapshot = try repository.snapshot(discoveredApplications: fixtures)
                    guard snapshot.entries.count >= 3 else { return }
                    if let folderID = try repository.createFolder(
                        draggedEntryID: snapshot.entries[2].id,
                        targetEntryID: snapshot.entries[1].id
                    ) {
                        try repository.renameFolder(id: folderID, name: "Fixture Folder")
                        try launcherViewModel.reloadSnapshot()
                    }
                } catch {
                    launcherViewModel.presentError(error)
                }
            }
            return
        }
#endif
        launcherViewModel.restoreCachedApplications()
        monitor.start(roots: settings.allScanRoots)
        startScheduledScanning()
        do {
            try hotKeyManager.register(settings.hotKey)
        } catch {
            launcherViewModel.presentError(error)
        }
        trackpadWakeService.start()
    }

    func stop() {
        scheduledScanTask?.cancel()
        scheduledScanTask = nil
        monitor.stop()
        hotKeyManager.unregister()
        trackpadWakeService.stop()
    }

    func reregisterHotKey() throws {
        try hotKeyManager.register(settings.hotKey)
    }

    func showSettings() {
        settingsWindowController.show()
    }

    private func startScheduledScanning() {
        scheduledScanTask?.cancel()
        scheduledScanTask = Task(priority: .background) { [weak launcherViewModel] in
            do {
                try await Task.sleep(for: ScanPolicy.initialDelay)
            } catch {
                return
            }

            while !Task.isCancelled {
                guard let launcherViewModel else { return }
                await launcherViewModel.rescan()
                do {
                    try await Task.sleep(for: ScanPolicy.periodicInterval)
                } catch {
                    return
                }
            }
        }
    }
}
