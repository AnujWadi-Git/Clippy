import AppKit
import Carbon.HIToolbox

/// Carbon `RegisterEventHotKey`: still the supported way to get a global shortcut. It needs no
/// Accessibility / Input Monitoring permission and works inside the sandbox.
final class GlobalHotkeyManager {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    /// Receives the id passed to `register` (1 = open panel, 2 = skip next copy).
    var onTrigger: ((UInt32) -> Void)?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let mgr = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { mgr.onTrigger?(hk.id) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    deinit { unregisterAll(); if let h = handlerRef { RemoveEventHandler(h) } }

    /// `modifiers` are Carbon flags (optionKey, cmdKey, shiftKey, controlKey).
    @discardableResult
    func register(id: UInt32 = 1, keyCode: Int, modifiers: Int) -> Bool {
        unregister(id: id)
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x434C5050) /* 'CLPP' */, id: id)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[id] = ref }
        return status == noErr
    }

    func unregister(id: UInt32) {
        if let r = refs[id] { UnregisterEventHotKey(r); refs[id] = nil }
    }

    func unregisterAll() { for id in Array(refs.keys) { unregister(id: id) } }

    // MARK: Display helpers
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.shift) { m |= shiftKey }
        return m
    }

    static func display(keyCode: Int, modifiers: Int) -> String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + keyName(keyCode)
    }

    private static func keyName(_ code: Int) -> String {
        let special: [Int: String] = [kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
                                      kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓"]
        if let s = special[code] { return s }
        let ansi: [Int: String] = [kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M",
            kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
            kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9", kVK_ANSI_Period: ".", kVK_ANSI_Comma: ","]
        return ansi[code] ?? "Key\(code)"
    }
}
