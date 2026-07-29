import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(environment: AppEnvironment) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LaunchpadX"
        window.titleVisibility = .visible
        window.contentView = NSHostingView(rootView: SettingsRootView(environment: environment))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
