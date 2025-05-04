import Foundation
import SwiftData

@Model
class Macro {
    var id = UUID()
    var name: String
    var keySequence: [MacroKey]
    var boundTo: MacroKey?
    var createdAt: Date
    @Attribute(.externalStorage) var steps: [MacroStep] = []
    
    init(name: String, keySequence: [MacroKey] = [], boundTo: MacroKey? = nil, steps: [MacroStep] = []) {
        self.id = UUID()
        self.name = name
        self.keySequence = keySequence
        self.boundTo = boundTo
        self.createdAt = Date()
        self.steps = steps
    }
}

struct MacroKey: Codable, Hashable, Identifiable {
    enum KeyType: String, Codable {
        case keyboard
        case mouse
    }
    
    // Custom coding keys to handle backward compatibility
    private enum CodingKeys: String, CodingKey {
        case type, keyCode, modifiers, isPressed, displayText
    }
    
    var id: UUID = UUID() // Unique identifier - not stored in Codable
    var type: KeyType
    var keyCode: Int
    var modifiers: Int // Bitmask for modifier keys (cmd, shift, etc.)
    var isPressed: Bool // For state tracking
    var displayText: String // Human-readable description
    var timestamp: Date = Date() // For ordering in sequences - not stored in Codable
    
    init(type: KeyType, keyCode: Int, modifiers: Int = 0, isPressed: Bool = true) {
        self.id = UUID()
        self.type = type
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isPressed = isPressed
        self.timestamp = Date()
        
        // Generate human-readable description
        switch type {
        case .keyboard:
            // Check if this is a modifier key itself
            if Self.isModifierKey(keyCode) {
                // For modifier keys, just show the symbol without duplicating
                self.displayText = Self.getCleanModifierName(keyCode)
            } else {
                // For regular keys, don't include modifiers in the display text
                // (modifiers will be shown separately in the UI)
                let keyName = Self.keyDescription(from: keyCode)
                
                // Use uppercase for single letter keys
                let finalKeyName = (keyName.count == 1) ? keyName.uppercased() : keyName
                
                self.displayText = finalKeyName
            }
        case .mouse:
            self.displayText = Self.mouseButtonDescription(from: keyCode)
        }
    }
    
    // Helper to check if a key is a modifier key
    private static func isModifierKey(_ keyCode: Int) -> Bool {
        return [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }
    
    // Helper to get a clean modifier key name (just the symbol)
    private static func getCleanModifierName(_ keyCode: Int) -> String {
        switch keyCode {
        case 54, 55: return "⌘"    // Command keys (both left and right)
        case 56, 60: return "⇧"    // Shift keys
        case 58, 61: return "⌥"    // Option keys
        case 59, 62: return "⌃"    // Control keys
        case 57: return "Caps Lock"
        case 63: return "Function"
        default: return "Key \(keyCode)"
        }
    }
    
    // Custom init from decoder to handle missing 'id' field
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(KeyType.self, forKey: .type)
        keyCode = try container.decode(Int.self, forKey: .keyCode)
        modifiers = try container.decode(Int.self, forKey: .modifiers)
        isPressed = try container.decode(Bool.self, forKey: .isPressed)
        displayText = try container.decode(String.self, forKey: .displayText)
        
        // These fields aren't in the stored data
        id = UUID()
        timestamp = Date()
    }
    
    // Custom encode method to omit id and timestamp
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encode(isPressed, forKey: .isPressed)
        try container.encode(displayText, forKey: .displayText)
    }
    
    // Helper methods to convert keycodes to readable descriptions
    private static func modifierDescription(from modifiers: Int) -> String {
        var parts: [String] = []
        
        if modifiers & 1 != 0 { parts.append("⇧") }
        if modifiers & 2 != 0 { parts.append("⌃") }
        if modifiers & 4 != 0 { parts.append("⌥") }
        if modifiers & 8 != 0 { parts.append("⌘") }
        
        return parts.joined(separator: "")
    }
    
    private static func keyDescription(from keyCode: Int) -> String {
        // Comprehensive key code mapping for macOS
        let keyCodes: [Int: String] = [
            // Letters
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 36: "Return",
            37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "n", 46: "m", 47: ".", 48: "Tab", 49: "Space",
            
            // Function keys
            50: "~", 51: "Delete", 53: "Escape", 54: "Right ⌘", 55: "Left ⌘",
            56: "Left ⇧", 57: "Caps Lock", 58: "Left ⌥", 59: "Left ⌃", 60: "Right ⇧",
            61: "Right ⌥", 62: "Right ⌃", 63: "Function",
            
            // More function keys (F1-F20)
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
            80: "F19", 90: "F20",
            
            // Keypad
            65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 71: "Keypad Clear",
            75: "Keypad /", 76: "Keypad Enter", 78: "Keypad -", 81: "Keypad =",
            82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3",
            86: "Keypad 4", 87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7",
            91: "Keypad 8", 92: "Keypad 9",
            
            // Special keys
            114: "Help", 115: "Home", 116: "Page Up", 117: "Delete Forward",
            119: "End", 121: "Page Down", 123: "Left Arrow", 124: "Right Arrow",
            125: "Down Arrow", 126: "Up Arrow"
        ]
        
        return keyCodes[keyCode] ?? "Key \(keyCode)"
    }
    
    private static func mouseButtonDescription(from buttonNumber: Int) -> String {
        switch buttonNumber {
        case 0: return "Left Click"
        case 1: return "Right Click"
        case 2: return "Middle Click"
        case 3: return "Mouse Button 4"
        case 4: return "Mouse Button 5"
        default: return "Mouse Button \(buttonNumber)"
        }
    }
}
