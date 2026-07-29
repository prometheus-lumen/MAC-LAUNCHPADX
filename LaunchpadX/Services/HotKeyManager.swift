import Carbon
import Foundation

protocol HotKeyManaging: AnyObject {
    var onPressed: (@Sendable () -> Void)? { get set }
    func register(_ hotKey: HotKey) throws
    func unregister()
}

enum HotKeyError: LocalizedError {
    case registrationFailed(OSStatus)

    var errorDescription: String? { String(localized: "The shortcut is unavailable. Choose a different shortcut.") }
}

@MainActor
final class HotKeyManager: NSObject, HotKeyManaging, @unchecked Sendable {
    var onPressed: (@Sendable () -> Void)?
    private var eventHandler: EventHandlerRef?
    private var registeredReference: EventHotKeyRef?
    private var identifier = EventHotKeyID(signature: OSType(0x4C504458), id: 1)

    func register(_ hotKey: HotKey) throws {
        unregister()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var identifier = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                if identifier.id == manager.identifier.id { manager.onPressed?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard installStatus == noErr else { throw HotKeyError.registrationFailed(installStatus) }
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &registeredReference
        )
        guard status == noErr else {
            unregister()
            throw HotKeyError.registrationFailed(status)
        }
    }

    func unregister() {
        if let reference = registeredReference { UnregisterEventHotKey(reference) }
        registeredReference = nil
        if let handler = eventHandler { RemoveEventHandler(handler) }
        eventHandler = nil
    }
}
