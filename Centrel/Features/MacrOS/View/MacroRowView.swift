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
            
            // Key sequence display - click to record
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
                Text(displayKeySequence.isEmpty ? "No keys recorded" : 
                    displayKeySequence.map { $0.displayText }.joined(separator: ", "))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
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
