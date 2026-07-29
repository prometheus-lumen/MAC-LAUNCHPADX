import AppKit
import Carbon
import SwiftUI

struct HotKeyRecorder: NSViewRepresentable {
    @Binding var hotKey: HotKey
    let requiresModifier: Bool
    let onCommit: (HotKey) -> Void

    func makeNSView(context: Context) -> KeyCaptureButton {
        let button = KeyCaptureButton()
        button.onCapture = onCommit
        button.requiresModifier = requiresModifier
        button.hotKey = hotKey
        return button
    }

    func updateNSView(_ nsView: KeyCaptureButton, context: Context) {
        nsView.hotKey = hotKey
    }
}

final class KeyCaptureButton: NSButton {
    var hotKey: HotKey = .defaultLauncher { didSet { title = hotKey.displayString } }
    var requiresModifier = true
    var onCapture: ((HotKey) -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 150, height: 30))
        bezelStyle = .rounded
        title = HotKey.defaultLauncher.displayString
        target = self
        action = #selector(beginRecording)
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() { title = String(localized: "Type Shortcut") ; window?.makeFirstResponder(self) }

    override func keyDown(with event: NSEvent) {
        let modifiers = HotKey.carbonModifiers(from: event.modifierFlags)
        guard (!requiresModifier || modifiers != 0), event.keyCode != 53 else { NSSound.beep(); return }
        let value = HotKey(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers)
        hotKey = value
        onCapture?(value)
    }

}
