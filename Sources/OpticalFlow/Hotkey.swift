import Carbon.HIToolbox

/// Global hotkeys through Carbon: no Accessibility or Input Monitoring permission.
enum Hotkey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var refs: [EventHotKeyRef?] = []
    private static var installed = false

    /// Registers one hotkey. Call once per key; a repeat for the same id replaces the action.
    static func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                // Carbon delivers hotkeys on the main thread.
                MainActor.assumeIsolated { Hotkey.actions[hotKeyID.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
        }
        let isNew = actions[id] == nil
        actions[id] = action
        guard isNew else { return }
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x4F46_4C57), id: id),
                            GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }

    /// Control-Option-Command-S: start or stop the session.
    static func registerSession(_ action: @escaping () -> Void) {
        register(id: 1, keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey | cmdKey), action: action)
    }

    /// Control-Space: the quick-entry panel.
    static func registerQuickEntry(_ action: @escaping () -> Void) {
        register(id: 2, keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey), action: action)
    }
}
