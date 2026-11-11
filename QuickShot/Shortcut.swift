//
//  Shortcut.swift
//  QuickShot
//

import AppKit
import Carbon.HIToolbox

/// A capture command the user can run from the menu or a global shortcut.
enum CaptureAction: String, CaseIterable, Identifiable, Codable {
    case fullScreen, selection, window, text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullScreen: return "Capture Full Screen"
        case .selection: return "Capture Selection"
        case .window: return "Capture Window"
        case .text: return "Capture Text"
        }
    }

    var detail: String {
        switch self {
        case .fullScreen: return "The display under the pointer"
        case .selection: return "Drag over any area"
        case .window: return "Click any window"
        case .text: return "Copy the text or QR code in an area"
        }
    }

    /// Identifies the registration with the system; must stay stable.
    var hotKeyID: UInt32 {
        switch self {
        case .fullScreen: return 1
        case .selection: return 2
        case .window: return 3
        case .text: return 4
        }
    }

    /// Offered in the welcome window. Nothing is registered until the user accepts.
    var suggestedShortcut: Shortcut? {
        switch self {
        case .fullScreen: return Shortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: [.command, .shift])
        case .selection: return Shortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: [.command, .shift])
        case .window, .text: return nil
        }
    }
}

/// A key plus modifiers, stored independently of the keyboard layout.
struct Shortcut: Codable, Equatable, Hashable {
    static let allowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var keyCode: UInt32
    var modifiers: UInt

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.allowedModifiers).rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifierFlags.contains(.command) { result |= UInt32(cmdKey) }
        if modifierFlags.contains(.shift) { result |= UInt32(shiftKey) }
        if modifierFlags.contains(.option) { result |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    /// A global shortcut must not swallow ordinary typing, so letters and digits need
    /// Command, Control or Option. Function keys may stand alone.
    var isValid: Bool {
        if Self.functionKeys.contains(keyCode) { return true }
        return !modifierFlags.intersection([.command, .control, .option]).isEmpty
    }

    var displayString: String {
        var text = ""
        if modifierFlags.contains(.control) { text += "⌃" }
        if modifierFlags.contains(.option) { text += "⌥" }
        if modifierFlags.contains(.shift) { text += "⇧" }
        if modifierFlags.contains(.command) { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    /// The character AppKit needs to show this shortcut beside a menu item, when it has one.
    var menuKeyEquivalent: String? {
        if let special = Self.menuCharacters[keyCode] { return special }
        let name = Self.keyName(keyCode)
        guard name.count == 1, Self.specialNames[keyCode] == nil else { return nil }
        return name.lowercased()
    }

    static func keyName(_ keyCode: UInt32) -> String {
        if let name = specialNames[keyCode] { return name }
        if let name = layoutKeyName(keyCode) { return name }
        return ansiNames[keyCode] ?? "Key \(keyCode)"
    }

    private static let functionKeys: Set<UInt32> = [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4), UInt32(kVK_F5), UInt32(kVK_F6),
        UInt32(kVK_F7), UInt32(kVK_F8), UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12)
    ]

    private static let specialNames: [UInt32: String] = [
        UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥", UInt32(kVK_Space): "Space", UInt32(kVK_Delete): "⌫",
        UInt32(kVK_Escape): "⎋", UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→", UInt32(kVK_DownArrow): "↓", UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_Home): "↖", UInt32(kVK_End): "↘", UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12"
    ]

    private static let menuCharacters: [UInt32: String] = [
        UInt32(kVK_Space): " ", UInt32(kVK_Return): "\r", UInt32(kVK_Tab): "\t"
    ]

    // Used only when the current layout cannot be read.
    private static let ansiNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
        35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 50: "`"
    ]

    /// The character this key produces on the active keyboard layout, so AZERTY and
    /// Dvorak users see the key they actually press.
    private static func layoutKeyName(_ keyCode: UInt32) -> String? {
        guard Thread.isMainThread,
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let name = String(utf16CodeUnits: characters, count: length).uppercased()
        return name.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).isEmpty ? nil : name
    }
}
