import AppKit
import Foundation

/// Uses only AppKit's public gesture events. macOS may reserve a configured
/// multi-touch gesture before it reaches an application, so Option-Space
/// remains the guaranteed global launcher shortcut.
@MainActor
final class TrackpadWakeService {
    var onFiveFingerPinch: (() -> Void)?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var lastTriggerDate = Date.distantPast
    private var lastFiveFingerTouchDate = Date.distantPast

    func start() {
        guard localMonitor == nil, globalMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.gesture, .magnify]) { [weak self] event in
            self?.handle(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.gesture, .magnify]) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        // Classic Launchpad uses thumb plus three fingers. Accepting five
        // fingers as well preserves LaunchpadX's existing user gesture.
        if event.type == .gesture, event.allTouches().count >= 4 {
            lastFiveFingerTouchDate = .now
            return
        }

        guard event.type == .magnify,
              abs(event.magnification) >= 0.06,
              Date.now.timeIntervalSince(lastFiveFingerTouchDate) <= 0.35,
              Date.now.timeIntervalSince(lastTriggerDate) > 0.9 else { return }
        lastTriggerDate = .now
        onFiveFingerPinch?()
    }
}
