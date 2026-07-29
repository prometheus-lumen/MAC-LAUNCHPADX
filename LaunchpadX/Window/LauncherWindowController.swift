import AppKit
import SwiftUI

@MainActor
final class LauncherWindowController: NSWindowController {
    private let viewModel: LauncherViewModel
    private let settings: SettingsStore

    init(viewModel: LauncherViewModel, settings: SettingsStore) {
        self.viewModel = viewModel
        self.settings = settings
        let panel = LauncherPanel()
        panel.contentView = NSHostingView(rootView: LauncherView(viewModel: viewModel, settings: settings))
        super.init(window: panel)
        viewModel.onDismiss = { [weak self] in self?.hide() }
    }

    required init?(coder: NSCoder) { nil }

    func toggle() {
        if window?.isVisible == true { hide() } else { show() }
    }

    func show() {
        guard let panel = window as? LauncherPanel else { return }
        let screen = selectedScreen()
        panel.setFrame(screen.frame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        viewModel.prepareForPresentation()
        let duration = motionDuration(normal: 0.22)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel = window else { return }
        viewModel.cancelTransientEditing()
        let duration = motionDuration(normal: 0.16)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            panel.animator().alphaValue = 0
        }, completionHandler: { Task { @MainActor in panel.orderOut(nil) } })
    }

    private func selectedScreen() -> NSScreen {
        let screens = NSScreen.screens
        let selected: NSScreen?
        switch settings.displayStrategy {
        case .cursor:
            selected = screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        case .primary:
            selected = NSScreen.main
        case .lastUsed:
            selected = screens.first { $0.displayID == settings.lastDisplayID }
        case .fixed:
            selected = screens.first { $0.displayID == settings.fixedDisplayID }
        }
        let screen = selected ?? NSScreen.main ?? screens[0]
        settings.lastDisplayID = screen.displayID
        return screen
    }

    private func motionDuration(normal: TimeInterval) -> TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : normal
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
