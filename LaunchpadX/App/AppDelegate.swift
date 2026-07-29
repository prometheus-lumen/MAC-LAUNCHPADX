import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()
    private var statusItem: NSStatusItem?
    private var shouldRun = true
    private var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains { $0.localizedCaseInsensitiveContains("xctest") }
            || ProcessInfo.processInfo.arguments.contains("--show-launcher-for-ui-testing")
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !isRunningUnderXCTest else { return }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let anotherInstance = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let anotherInstance else { return }
        anotherInstance.activate(options: [.activateAllWindows])
        shouldRun = false
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard shouldRun else { return }
        applyApplicationIcon()
        applyActivationPolicy()
        configureStatusItem()
        environment.start()
        if ProcessInfo.processInfo.arguments.contains("--show-launcher-for-ui-testing") {
            DispatchQueue.main.async { [weak self] in
                self?.environment.launcherWindowController.show()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment.launcherWindowController.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.monitor.stop()
        environment.hotKeyManager.unregister()
        environment.trackpadWakeService.stop()
    }

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(.regular)
    }

    private func applyApplicationIcon() {
        if let icon = NSImage(named: NSImage.Name("AppIcon")) {
            NSApp.applicationIconImage = icon
        }
    }

    func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let icon = NSApp.applicationIconImage {
            icon.size = NSSize(width: 18, height: 18)
            item.button?.image = icon
        }
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Open LaunchpadX"), action: #selector(openLauncher), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Settings"), action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: String(localized: "Rescan Applications"), action: #selector(rescan), keyEquivalent: "r")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: String(localized: "Quit LaunchpadX"), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func openLauncher() { environment.launcherWindowController.show() }
    @objc private func openSettings() { environment.showSettings() }
    @objc private func rescan() { Task { await environment.launcherViewModel.rescan() } }
    @objc private func quit() { NSApp.terminate(nil) }
}
