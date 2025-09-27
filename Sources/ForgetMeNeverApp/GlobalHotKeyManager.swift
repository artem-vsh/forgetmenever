import Carbon
import Foundation

final class GlobalHotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let handler: () -> Void

    init(hotKey: AppConfig.HotKeyConfig, handler: @escaping () -> Void) throws {
        self.handler = handler
        try register(hotKey: hotKey)
    }

    deinit {
        unregister()
    }

    func update(hotKey: AppConfig.HotKeyConfig) throws {
        unregister()
        try register(hotKey: hotKey)
    }

    private func register(hotKey: AppConfig.HotKeyConfig) throws {
        var eventHotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType("FMN1".fourCharCodeValue), id: UInt32(1))

        let status = RegisterEventHotKey(
            UInt32(hotKey.keyCode),
            hotKey.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &eventHotKeyRef
        )

        guard status == noErr, let registeredRef = eventHotKeyRef else {
            throw HotKeyError.registrationFailed(status)
        }

        hotKeyRef = registeredRef
        installEventHandler()
    }

    private func installEventHandler() {
        uninstallEventHandler()
        var eventType = EventTypeSpec(eventClass: UInt32(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()

        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handleHotKey(event: eventRef)
            return noErr
        }

        var handlerRef: EventHandlerRef?
        InstallEventHandler(GetEventDispatcherTarget(), callback, 1, &eventType, userData, &handlerRef)
        eventHandlerRef = handlerRef
    }

    private func uninstallEventHandler() {
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func handleHotKey(event: EventRef?) {
        handler()
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        uninstallEventHandler()
    }

    enum HotKeyError: Error {
        case registrationFailed(OSStatus)
    }
}

private extension String {
    var fourCharCodeValue: FourCharCode {
        var result: FourCharCode = 0
        for scalar in unicodeScalars {
            result = (result << 8) + FourCharCode(scalar.value)
        }
        return result
    }
}
