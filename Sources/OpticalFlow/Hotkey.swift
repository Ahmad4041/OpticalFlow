import Carbon.HIToolbox

/// One global hotkey through Carbon: no Accessibility or Input Monitoring permission.
enum Hotkey {
    private static var action: (() -> Void)?
    private static var ref: EventHotKeyRef?

    /// Control-Option-Command-S by default.
    static func register(keyCode: UInt32 = UInt32(kVK_ANSI_S),
                         modifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey),
                         action: @escaping () -> Void) {
        self.action = action
        guard ref == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Carbon delivers hotkeys on the main thread.
            MainActor.assumeIsolated { Hotkey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4F46_4C57), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
}
