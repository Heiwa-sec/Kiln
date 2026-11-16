import AppKit
import Carbon.HIToolbox

/// One global hotkey through the Carbon hot-key API: public, and it needs no permission (see SPIKE.md).
enum HotKey {
    nonisolated(unsafe) static var onPress: (@MainActor () -> Void)?
    nonisolated(unsafe) private static var ref: EventHotKeyRef?
    nonisolated(unsafe) private static var installed = false

    static func carbonModifiers(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }; if f.contains(.shift) { m |= UInt32(shiftKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }; if f.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    /// Returns false when the system refused the combination (already taken by another app, for instance).
    @discardableResult
    static func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.onPress?() } }
                return noErr
            }, 1, &spec, nil, nil)
            installed = true
        }
        return RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: 0x4b494c4e, id: 1), GetApplicationEventTarget(), 0, &ref) == noErr
    }
}
