import Carbon

/// A system-wide shortcut through Carbon's hot key API, which needs no accessibility
/// permission. Lives as long as the object does.
final class HotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// ⌃⌥⌘U by default: clear of the shortcuts common apps ship with.
    init(keyCode: UInt32 = UInt32(kVK_ANSI_U),
         modifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey),
         action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let id = EventHotKeyID(signature: OSType(0x434D_5452), id: 1) // 'CMTR'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
