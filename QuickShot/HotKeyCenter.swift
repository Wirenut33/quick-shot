//
//  HotKeyCenter.swift
//  QuickShot
//

import AppKit
import Carbon.HIToolbox

/// Registers system-wide shortcuts. This API needs no Accessibility permission and
/// works inside the App Sandbox.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private static let signature: OSType = 0x5153_4854 // "QSHT"
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?

    private init() {}

    /// Returns false when the system refuses the shortcut, for example because this
    /// app already holds it under another identifier.
    @discardableResult
    func register(id: UInt32, shortcut: Shortcut, action: @escaping () -> Void) -> Bool {
        unregister(id: id)
        installHandlerIfNeeded()
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetEventDispatcherTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { return false }
        references[id] = reference
        actions[id] = action
        return true
    }

    func unregister(id: UInt32) {
        if let reference = references.removeValue(forKey: id) {
            UnregisterEventHotKey(reference)
        }
        actions[id] = nil
    }

    func unregisterAll() {
        Array(references.keys).forEach(unregister)
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyPressed, 1, &spec, nil, &handler)
    }

    /// Shortcuts macOS itself has claimed and enabled (screenshots, Spotlight, Mission
    /// Control and so on). Other apps' shortcuts cannot be discovered.
    static func systemReservedShortcuts() -> [(keyCode: UInt32, carbonModifiers: UInt32)] {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = unmanaged?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int else { return nil }
            return (UInt32(truncatingIfNeeded: code), UInt32(truncatingIfNeeded: modifiers))
        }
    }

    static func isReservedBySystem(_ shortcut: Shortcut) -> Bool {
        systemReservedShortcuts().contains { $0.keyCode == shortcut.keyCode && $0.carbonModifiers == shortcut.carbonModifiers }
    }
}

// Carbon calls this on the main thread. It only reads the identifier and hands off.
private func hotKeyPressed(_ call: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr else { return status }
    let id = identifier.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated { HotKeyCenter.shared.fire(id) }
    }
    return noErr
}
