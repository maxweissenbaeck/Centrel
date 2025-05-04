import SwiftUI
import OSLog
import AppKit

// Create an app-wide event manager that can be shared across views
class AppEventsManager {
    static let shared = AppEventsManager()
    private var eventMonitor: Any?
    private var focusCallbacks: [UUID: () -> Void] = [:]
    
    private init() {
        setupGlobalMonitor()
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func setupGlobalMonitor() {
        // This monitors ALL mouse down events in the application
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // Notify all callbacks that a click occurred
            self?.focusCallbacks.values.forEach { callback in
                callback()
            }
            
            // Allow the event to continue (return it unchanged)
            return event
        }
    }
    
    // Register for notification of clicks anywhere in the app
    func registerForClickEvents(id: UUID, callback: @escaping () -> Void) -> Void {
        focusCallbacks[id] = callback
    }
    
    // Remove registration when no longer needed
    func unregisterForClickEvents(id: UUID) {
        focusCallbacks.removeValue(forKey: id)
    }
}

// Modifier to connect a view to the app event manager
struct ClickOutsideModifier: ViewModifier {
    let id: UUID
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                AppEventsManager.shared.registerForClickEvents(id: id) {
                    action()
                }
            }
            .onDisappear {
                AppEventsManager.shared.unregisterForClickEvents(id: id)
            }
    }
}

extension View {
    func onClickOutside(id: UUID, perform action: @escaping () -> Void) -> some View {
        self.modifier(ClickOutsideModifier(id: id, action: action))
    }
}

struct MacroRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var macro: Macro
    var controller: MacroController
    var onBindMacro: (Macro) -> Void
    @State private var showDeleteConfirmation = false
    @State private var isEditingName: Bool
    @State private var editedName = ""
    @State private var isRecordingSequence = false
    @State private var isRecordingBinding = false
    @FocusState private var nameFieldIsFocused: Bool
    @State private var rowID = UUID() // Unique ID for this row
    var onEditComplete: (() -> Void)? = nil
    
    // Add logger for debugging
    private let logger = Logger(subsystem: "com.centrel.macros", category: "MacroRowView")
    
    // Initialize with optional auto-edit mode for newly created macros
    init(macro: Macro, controller: MacroController, isEditingName: Bool = false, onEditComplete: (() -> Void)? = nil, onBindMacro: @escaping (Macro) -> Void) {
        self.macro = macro
        self.controller = controller
        self.onBindMacro = onBindMacro
        self.onEditComplete = onEditComplete
        self._isEditingName = State(initialValue: isEditingName)
        self._editedName = State(initialValue: macro.name)
    }
    
    // Computed property to get only key down events for display purposes
    private var displayKeySequence: [MacroKey] {
        return macro.keySequence.filter { $0.isPressed }
    }
    
    // Computed property to create a readable string from macro steps
    private var stepsDisplayText: String {
        if !macro.steps.isEmpty {
            // Show only clean symbols for each step
            return macro.steps.map { step in
                switch step.type {
                case .key:
                    // Get just the key symbol without any extra text
                    let keyCode = step.keyCode ?? 0
                    
                    // For modifier keys, return their symbol only
                    if keyCode >= 54 && keyCode <= 62 {
                        // Map modifier key codes directly to symbols
                        switch keyCode {
                        case 54, 55: return "⌘" // Command keys
                        case 56, 60: return "⇧" // Shift keys
                        case 58, 61: return "⌥" // Option keys
                        case 59, 62: return "⌃" // Control keys
                        case 57: return "⇪"     // Caps Lock
                        default: return ""
                        }
                    }
                    
                    // For letter/number keys with modifiers, show modifiers + key
                    var modText = ""
                    let mods = step.modifiers
                    
                    // Add modifier symbols in consistent order
                    if mods & 1 != 0 { modText += "⇧" } // Shift
                    if mods & 2 != 0 { modText += "⌃" } // Control
                    if mods & 4 != 0 { modText += "⌥" } // Option/Alt
                    if mods & 8 != 0 { modText += "⌘" } // Command
                    
                    // Get clean key name (just the letter/symbol)
                    let keyName = cleanKeyName(keyCode)
                    
                    return modText.isEmpty ? keyName : "\(modText)\(keyName)"
                    
                case .mouse:
                    // Simple mouse button display
                    let buttonNum = step.keyCode ?? 0
                    switch buttonNum {
                    case 0: return "Click"
                    case 1: return "Right Click"
                    case 2: return "Middle Click"
                    default: return "Button \(buttonNum)"
                    }
                    
                case .text:
                    return step.text ?? ""
                    
                case .delay:
                    return "" // Don't show delays in the UI
                }
            }
            .filter { !$0.isEmpty } // Remove empty entries
            .joined(separator: " ")
        } else {
            // Fallback for old-style macros
            return displayKeySequence
                .filter { $0.isPressed }
                .map { cleanKeyDisplay($0.displayText) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }
    
    // Helper to convert keycode to a clean key name (just the letter/symbol)
    private func cleanKeyName(_ keyCode: Int) -> String {
        // Map key codes to simple key names
        let keyCodes: [Int: String] = [
            // Letters
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
            
            // Common function keys
            51: "Delete", 53: "Esc", 63: "Fn",
            
            // Arrows - use simple arrows
            123: "←", 124: "→", 125: "↓", 126: "↑",
            
            // Function keys
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        
        return keyCodes[keyCode] ?? ""
    }
    
    // Clean up key display by removing Left/Right and other extra text
    private func cleanKeyDisplay(_ text: String) -> String {
        // Remove "Left" and "Right" labels
        var cleaned = text.replacingOccurrences(of: "Left ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "Right ", with: "")
        
        // Replace full names with symbols
        cleaned = cleaned.replacingOccurrences(of: "Command", with: "⌘")
        cleaned = cleaned.replacingOccurrences(of: "Shift", with: "⇧")
        cleaned = cleaned.replacingOccurrences(of: "Control", with: "⌃")
        cleaned = cleaned.replacingOccurrences(of: "Option", with: "⌥")
        cleaned = cleaned.replacingOccurrences(of: "Caps Lock", with: "⇪")
        
        // Remove " + " separator if present
        cleaned = cleaned.replacingOccurrences(of: " + ", with: "")
        
        return cleaned
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Macro name - editable on double click
            if isEditingName {
                TextField("Macro name", text: $editedName)
                    .textFieldStyle(.roundedBorder) // Standard macOS border
                    .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                    .focused($nameFieldIsFocused)
                    .onSubmit {
                        logger.info("TextField submit triggered for macro: \(macro.name)")
                        saveName()
                    }
                    .onExitCommand {
                        logger.info("TextField exit command triggered for macro: \(macro.name)")
                        saveName()
                    }
                    .onAppear {
                        logger.info("TextField appeared for macro: \(macro.name), setting focus")
                        nameFieldIsFocused = true
                        // Auto-select the text when editing starts
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSResponder.selectAll(_:)), with: nil)
                        }
                    }
                    // Add a background hit area that captures taps on the textfield
                    .background(
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .allowsHitTesting(false)
                    )
            } else {
                Text(macro.name)
                    .font(.body) // Standard non-bold font
                    .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        logger.info("Double-tap detected on macro name: \(macro.name)")
                        startEditing()
                    }
            }
            
            // Key sequence - show in a readable format
            if isRecordingSequence {
                HStack {
                    Image(systemName: "record.circle.fill")
                        .foregroundColor(.red)
                    Text("Recording...")
                        .foregroundColor(.red)
                }
                .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    setupSequenceRecording()
                }
            } else {
                Text(stepsDisplayText)
                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(stepsDisplayText)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isRecordingSequence = true
                    }
            }
            
            // Binding status/button
            HStack {
                if isRecordingBinding {
                    HStack {
                        Image(systemName: "record.circle.fill")
                            .foregroundColor(.red)
                        Text("Press key or Delete to clear...")
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.red.opacity(0.5), lineWidth: 1)
                            .background(Color.red.opacity(0.1).cornerRadius(4))
                    )
                    .onAppear {
                        setupBindingRecording()
                    }
                } else if let boundTo = macro.boundTo {
                    Text(boundTo.displayText)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.blue.opacity(0.5), lineWidth: 1)
                                .background(Color.blue.opacity(0.1).cornerRadius(4))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Changed: Start recording a new binding instead of executing
                            isRecordingBinding = true
                        }
                } else {
                    Text("Click to bind")
                        .foregroundColor(.gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.gray.opacity(0.5), lineWidth: 1)
                                .background(Color.gray.opacity(0.1).cornerRadius(4))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isRecordingBinding = true
                        }
                }
            }
            .frame(width: 120, alignment: .leading)
            
            // Execute and Delete buttons
            HStack(spacing: 12) {
                // Execute button
                Button(action: {
                    executeCurrentMacro()
                }) {
                    Image(systemName: "play.fill")
                        .foregroundColor(.green)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Delete button
                Button(action: {
                    showDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: 80, alignment: .center)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onChange(of: nameFieldIsFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused {
                saveName()
            }
        }
        .onChange(of: isEditingName) { oldValue, newValue in
            logger.info("isEditingName changed: was \(oldValue), now \(newValue) for macro: \(macro.name)")
            if oldValue && !newValue {
                // If we just exited editing mode, call the completion handler
                logger.info("Editing ended - calling completion handler for macro: \(macro.name)")
                onEditComplete?()
            }
        }
        // Register with the global event manager for clicks
        .onClickOutside(id: rowID) {
            logger.info("Global click detected - checking if we need to save for macro: \(macro.name)")
            if isEditingName && nameFieldIsFocused {
                logger.info("We were editing, saving name...")
                // Short delay to let the click process first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    nameFieldIsFocused = false
                    saveName()
                }
            }
        }
        // Use a tap gesture on the row itself
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditingName && nameFieldIsFocused {
                logger.info("Tap detected on row while editing - forcing end of edit mode for macro: \(macro.name)")
                // Save and unfocus
                nameFieldIsFocused = false
                saveName()
            }
        }
        .confirmationDialog(
            "Delete Macro",
            isPresented: $showDeleteConfirmation,
            actions: {
                Button("Delete", role: .destructive) {
                    deleteMacro()
                }
            },
            message: {
                Text("Are you sure you want to delete '\(macro.name)'? This action cannot be undone.")
            }
        )
    }
    
    private func startEditing() {
        logger.info("Starting edit mode for macro: \(macro.name)")
        editedName = macro.name
        isEditingName = true
    }
    
    private func saveName() {
        // Avoid duplicate saves
        if !isEditingName {
            return
        }
        
        logger.info("saveName() called for macro: \(macro.name), new name: \(editedName)")
        if !editedName.isEmpty {
            macro.name = editedName
            do {
                try modelContext.save()
                logger.info("Successfully saved name change to database")
            } catch {
                logger.error("Failed to save name to database: \(error.localizedDescription)")
            }
        } else {
            logger.info("Name was empty, not saving")
        }
        
        logger.info("Ending edit mode")
        isEditingName = false
        nameFieldIsFocused = false
    }
    
    private func deleteMacro() {
        modelContext.delete(macro)
        try? modelContext.save()
    }
    
    private func setupSequenceRecording() {
        // Clear existing sequence first
        macro.keySequence = []
        
        // Start recording key sequence
        controller.startRecording { newKey in
            // Always add key events to the sequence, both up and down
            macro.keySequence.append(newKey)
            try? modelContext.save()
        }
        
        // Stop recording after 3 seconds or when user presses ESC
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if isRecordingSequence {
                stopSequenceRecording()
            }
        }
    }
    
    private func stopSequenceRecording() {
        isRecordingSequence = false
        _ = controller.stopRecording()
    }
    
    private func setupBindingRecording() {
        controller.startRecording { newKey in
            // Check if Delete key was pressed to clear the binding
            if newKey.type == .keyboard && newKey.keyCode == 51 && newKey.isPressed { // 51 is Delete key
                // Clear binding
                macro.boundTo = nil
                try? modelContext.save()
                isRecordingBinding = false
                _ = controller.stopRecording()
                
                print("Cleared binding for macro: \(macro.name)")
                return
            }
            
            // Only set the binding on key down events
            if newKey.isPressed {
                macro.boundTo = newKey
                try? modelContext.save()
                isRecordingBinding = false
                _ = controller.stopRecording()
            }
        }
        
        // Stop recording after 3 seconds if nothing is pressed
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if isRecordingBinding {
                isRecordingBinding = false
                _ = controller.stopRecording()
            }
        }
    }
    
    private func executeCurrentMacro() {
        print("DEBUG: Attempting to execute macro: \(macro.name) with \(macro.keySequence.count) keys")
        
        // Debug code - print the keys in the sequence
        for (index, key) in macro.keySequence.enumerated() {
            print("DEBUG: Key \(index): \(key.displayText) (code: \(key.keyCode), type: \(key.type), \(key.isPressed ? "DOWN" : "UP"))")
        }
        
        // Ensure the macro is actually executed with force flag
        controller.executeMacro(macro, forceExecution: true)
    }
} 
