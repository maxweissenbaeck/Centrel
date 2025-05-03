import Foundation
import SwiftUI
import AppKit
import SwiftData
import OSLog

@Observable
class MacroController {
    var isRecording = false
    var isDebugging = false
    var recordedKeys: [MacroKey] = []
    var currentlyPressedKeys: [MacroKey] = []
    var currentMacroName: String = ""
    var macros: [Macro] = [] // Store all macros for trigger detection
    
    // Flag to prevent nested macro execution
    var isExecutingMacro = false
    
    // For debugging
    var lastPressedKey: MacroKey?
    var permissionGranted = false
    var errorMessage: String?
    var hasShownPermissionBanner = false
    var useSimulation = false // Add flag to control simulation
    private let logger = Logger(subsystem: "com.centrel.macros", category: "MacroController")
    
    // Track previous modifier state to detect changes
    private var previousModifiers: NSEvent.ModifierFlags = []
    
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var localMouseMonitor: Any?
    private var checkTimer: Timer?
    private var flagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var modelContext: ModelContext?
    
    // Timer for simulating key presses in a sandboxed environment
    private var simulationTimer: Timer?
    
    // Private property to store the callback
    private var onKeyRecordedCallback: ((MacroKey) -> Void)?
    
    init() {
        // Check permission state immediately
        checkInputMonitoringPermission(tryPrompt: false)
        setupLocalMonitors()
        
        // Try to setup monitoring immediately to test permission
        trySetupMonitoring()
        
        // Start a timer to periodically check permission status
        checkTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkInputMonitoringPermission(tryPrompt: false)
            self?.verifyPermissionByMonitoring()
        }
        
        // Start refreshing macros every 5 seconds but only if we have a context
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, self.modelContext != nil else { return }
            self.refreshMacros()
        }
    }
    
    // Set up model context for macro access
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        refreshMacros()
        
        // Log immediately after setting the context and refreshing
        if isDebugging {
            logger.info("ModelContext set and macros refreshed")
            logStoredMacros()
        }
    }
    
    // Refresh the list of macros for trigger detection
    func refreshMacros() {
        guard let modelContext = modelContext else {
            // Only log this when debugging is enabled to avoid console spam
            if isDebugging {
                logger.error("Failed to refresh macros: ModelContext is nil")
            }
            return
        }
        
        do {
            let descriptor = FetchDescriptor<Macro>()
            self.macros = try modelContext.fetch(descriptor)
            print("Loaded \(self.macros.count) macros for trigger detection")
            
            // Log the macros if debugging is enabled
            if isDebugging {
                logStoredMacros()
            }
        } catch {
            print("Failed to load macros: \(error)")
            logger.error("Failed to load macros: \(error.localizedDescription)")
        }
    }
    
    deinit {
        stopMonitoring()
        stopKeySimulation()
        checkTimer?.invalidate()
    }
    
    // Check if we have permission to monitor input
    private func checkInputMonitoringPermission(tryPrompt: Bool) {
        // Option to prompt the user if needed
        let checkOptions: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: tryPrompt]
        let newPermissionStatus = AXIsProcessTrustedWithOptions(checkOptions)
        
        if newPermissionStatus != permissionGranted {
            permissionGranted = newPermissionStatus
            
            if permissionGranted {
                errorMessage = nil
                hasShownPermissionBanner = true
                // Try to set up global monitors if we are debugging/recording
                if isDebugging || isRecording {
                    startMonitoring()
                }
                
                // Stop simulation if we now have permission
                stopKeySimulation()
            }
        }
    }
    
    // Additional verification by attempting to set up monitors
    private func verifyPermissionByMonitoring() {
        if !permissionGranted {
            // Try to set up a temporary monitor to verify permissions
            let testMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { _ in
                // This will never get called, we're just testing if we can create the monitor
            }
            
            if testMonitor != nil {
                // If we got here, we have permission!
                NSEvent.removeMonitor(testMonitor!)
                permissionGranted = true
                hasShownPermissionBanner = true
                errorMessage = nil
                
                // Now that we know we have permission, start monitoring if needed
                if isDebugging || isRecording {
                    startMonitoring()
                }
            }
        }
    }
    
    // Try to set up monitoring once to check permission
    private func trySetupMonitoring() {
        if !permissionGranted {
            // Try to set up a test monitor
            let testMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { _ in }
            
            if testMonitor != nil {
                NSEvent.removeMonitor(testMonitor!)
                // If we reach here, we have permission
                permissionGranted = true
                hasShownPermissionBanner = true
            }
        }
    }
    
    // Request permission explicitly
    func requestPermission() {
        // This version will show the permission prompt
        checkInputMonitoringPermission(tryPrompt: true)
    }
    
    // Setup local monitors (these work even in a sandboxed app)
    private func setupLocalMonitors() {
        // Local monitors only work when app is in focus
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
        
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
        
        // Add monitor for modifier flag changes (shift, ctrl, alt, cmd, fn, caps)
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }
    
    // Simulate some key presses (for testing)
    private func startKeySimulation() {
        stopKeySimulation()
        
        // Only use simulation if we don't have permission AND simulation is enabled
        if permissionGranted || !useSimulation {
            return
        }
        
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.simulateRandomKeyPress()
        }
    }
    
    private func stopKeySimulation() {
        simulationTimer?.invalidate()
        simulationTimer = nil
    }
    
    private func simulateRandomKeyPress() {
        // Only simulate if debugging is enabled and we don't have permissions
        guard isDebugging && !permissionGranted && useSimulation else { return }
        
        let testKeys = [
            MacroKey(type: .keyboard, keyCode: 0, modifiers: 0, isPressed: true),  // 'a'
            MacroKey(type: .keyboard, keyCode: 7, modifiers: 8, isPressed: true),  // 'cmd+x'
            MacroKey(type: .keyboard, keyCode: 36, modifiers: 0, isPressed: true), // 'return'
            MacroKey(type: .keyboard, keyCode: 123, modifiers: 0, isPressed: true), // Left arrow
            MacroKey(type: .keyboard, keyCode: 53, modifiers: 0, isPressed: true), // Escape
            MacroKey(type: .keyboard, keyCode: 49, modifiers: 0, isPressed: true), // Space
            MacroKey(type: .keyboard, keyCode: 126, modifiers: 0, isPressed: true), // Up arrow
            
            // Simulate modifier key presses
            MacroKey(type: .keyboard, keyCode: 56, modifiers: 0, isPressed: true), // Left Shift
            MacroKey(type: .keyboard, keyCode: 59, modifiers: 0, isPressed: true), // Left Control
            MacroKey(type: .keyboard, keyCode: 58, modifiers: 0, isPressed: true), // Left Option
            MacroKey(type: .keyboard, keyCode: 55, modifiers: 0, isPressed: true), // Left Command
            MacroKey(type: .keyboard, keyCode: 63, modifiers: 0, isPressed: true), // Function
            MacroKey(type: .keyboard, keyCode: 57, modifiers: 0, isPressed: true), // Caps Lock
            
            MacroKey(type: .mouse, keyCode: 2, modifiers: 0, isPressed: true)      // 'middle click'
        ]
        
        if let randomKey = testKeys.randomElement() {
            DispatchQueue.main.async {
                self.lastPressedKey = randomKey
                self.currentlyPressedKeys.append(randomKey)
                
                // Remove the key after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.currentlyPressedKeys.removeAll { $0.displayText == randomKey.displayText }
                }
            }
        }
    }
    
    // Toggle simulation mode for testing
    func toggleSimulation() {
        useSimulation.toggle()
        if useSimulation && isDebugging && !permissionGranted {
            startKeySimulation()
        } else {
            stopKeySimulation()
        }
    }
    
    // Start recording a new macro
    func startRecording(macroName: String) {
        guard !isRecording else { return }
        
        currentMacroName = macroName
        recordedKeys.removeAll()
        isRecording = true
        
        // Log start of recording
        if isDebugging {
            logger.info("🎬 Started recording macro: \(macroName)")
        }
        
        startMonitoring()
    }
    
    // Start recording with a callback for each key
    func startRecording(onKeyRecorded: @escaping (MacroKey) -> Void) {
        guard !isRecording else { return }
        
        recordedKeys.removeAll()
        isRecording = true
        
        // Set up a callback for each recorded key
        self.onKeyRecordedCallback = onKeyRecorded
        
        // Log start of recording
        if isDebugging {
            logger.info("🎬 Started recording with callback")
        }
        
        startMonitoring()
    }
    
    // Stop recording and save the macro
    func stopRecording() -> Macro? {
        guard isRecording else {
            return nil
        }
        
        isRecording = false
        stopMonitoring()
        
        // Log the recorded keys for debugging
        if isDebugging {
            logger.info("🛑 Stopped recording. \(self.recordedKeys.count) keys recorded:")
            for (index, key) in self.recordedKeys.enumerated() {
                logger.info("🎥 Recorded key #\(index+1): \(key.displayText) (\(key.isPressed ? "DOWN" : "UP"))")
            }
        }
        
        // Remove the last left mouse click if it's likely the click to stop recording
        if let lastKey = self.recordedKeys.last, 
           lastKey.type == .mouse && 
           lastKey.keyCode == 0 && // Left click
           lastKey.isPressed {
            
            self.recordedKeys.removeLast()
            if isDebugging {
                logger.info("🧹 Removed final left-click that was likely used to stop recording")
            }
        }
        
        if self.recordedKeys.isEmpty {
            onKeyRecordedCallback = nil
            return nil
        }
        
        let newMacro = Macro(name: currentMacroName, keySequence: self.recordedKeys)
        currentMacroName = ""
        
        // Clear the callback
        onKeyRecordedCallback = nil
        
        return newMacro
    }
    
    // Toggle debugging mode
    func toggleDebugging() {
        isDebugging.toggle()
        
        if isDebugging {
            startMonitoring()
            
            // Log all currently stored macros when debugging starts
            logStoredMacros()
            
            // Only start simulation if we don't have permission AND simulation is enabled
            if !permissionGranted && useSimulation {
                startKeySimulation()
            }
            
            // Clear any stale pressed keys
            currentlyPressedKeys.removeAll()
        } else {
            if !isRecording {
                stopMonitoring()
            }
            stopKeySimulation()
        }
    }
    
    // Log all currently stored macros - with explicit refresh
    private func logStoredMacros() {
        // Force a refresh of macros from database before logging
        if let modelContext = modelContext {
            do {
                let descriptor = FetchDescriptor<Macro>()
                let dbMacros = try modelContext.fetch(descriptor)
                self.macros = dbMacros // Ensure we're using the freshest data
                logger.info("📋 === STORED MACROS (\(self.macros.count)) ===")
                logger.info("📋 Verified \(dbMacros.count) macros in database")
                
                for (index, macro) in self.macros.enumerated() {
                    logger.info("📋 Macro #\(index+1): \"\(macro.name)\" - \(macro.keySequence.count) keys")
                    if let boundTo = macro.boundTo {
                        logger.info("📋 - Bound to: \(boundTo.displayText)")
                    } else {
                        logger.info("📋 - Not bound to any key")
                    }
                    
                    // Log the key sequence
                    for (keyIndex, key) in macro.keySequence.enumerated() {
                        logger.info("📋 - Key #\(keyIndex+1): \(key.displayText) (\(key.isPressed ? "DOWN" : "UP"))")
                    }
                }
            } catch {
                logger.error("📋 Error fetching macros from database: \(error.localizedDescription)")
            }
        } else {
            logger.error("📋 Cannot log macros: ModelContext is nil")
        }
    }
    
    // Bind a macro to a specific key
    func bindMacroToKey(_ macro: Macro, key: MacroKey) {
        macro.boundTo = key
    }
    
    // Execute a macro
    func executeMacro(_ macro: Macro, forceExecution: Bool = false) {
        // Check if the macro has any key sequence to execute
        guard !macro.keySequence.isEmpty else {
            print("Cannot execute macro: No key sequence defined")
            return
        }
        
        // Prevent nested macro execution to avoid infinite loops
        guard !isExecutingMacro else {
            if isDebugging {
                logger.info("⚠️ Prevented nested macro execution: already executing a macro")
            }
            return
        }
        
        // Make sure we have permission to control the computer
        if !permissionGranted && !forceExecution {
            print("⚠️ Cannot execute macro: No permission to control the computer")
            errorMessage = "Permission required to execute macros. Enable in Privacy settings."
            return
        }
        
        // Clear any previous error messages
        errorMessage = nil
        
        // Log the macro we're about to execute
        if isDebugging {
            logger.info("DEBUG: Attempting to execute macro: \(macro.name) with \(macro.keySequence.count) keys")
            for (index, key) in macro.keySequence.enumerated() {
                logger.info("DEBUG: Key \(index): \(key.displayText) (code: \(key.keyCode), type: \(key.type.rawValue))")
            }
        }
        
        print("Executing macro: \(macro.name) with \(macro.keySequence.count) keys")
        
        // Set the flag to prevent nested macro execution
        isExecutingMacro = true
        
        // Try multiple execution methods in order of reliability
            do {
            try executeStandardMethod(macro)
            } catch {
            logger.error("Standard method failed, trying fallback method: \(error.localizedDescription)")
            
            // Method 2: Try using AppleScript if available
            if executeWithAppleScript(macro) {
                logger.info("Successfully executed macro with AppleScript")
                // Reset the flag when done
                isExecutingMacro = false
                return
        }
        
            // Method 3: Last resort - try the most permissive approach
            executeLastResortMethod(macro)
        }
        
        print("Macro execution completed")
        
        // Reset the flag when done
        isExecutingMacro = false
    }
    
    // Method 1: The standard CGEvent method we've been using
    private func executeStandardMethod(_ macro: Macro) throws {
        // Execute key events in the exact sequence they were recorded
        for key in macro.keySequence {
            if isDebugging {
                logger.info("▶️ Executing: \(key.displayText) (\(key.isPressed ? "DOWN" : "UP"))")
            }
            
            do {
                if key.isPressed {
                    try executeKeyDown(key, forceExecution: true)
                    // Log success for debugging
                    if isDebugging {
                        logger.info("✓ Successfully posted keyDown event")
                    }
                } else {
                    try executeKeyUp(key, forceExecution: true)
                    // Log success for debugging
                    if isDebugging {
                        logger.info("✓ Successfully posted keyUp event")
                    }
                }
                // Small delay between key events
                usleep(20000) // 20ms between events
            } catch {
                logger.error("❌ Failed to execute key event: \(error.localizedDescription)")
                errorMessage = "Failed to execute key event in macro"
                throw error
            }
        }
    }
    
    // Method 2: Try using AppleScript to simulate key presses
    private func executeWithAppleScript(_ macro: Macro) -> Bool {
        // Group sequences of key downs and ups into sensible keystrokes
        let keySequence = macro.keySequence
        var index = 0
        var success = true
        
        while index < keySequence.count {
            let currentKey = keySequence[index]
            if currentKey.isPressed {
                // Find the corresponding key up if it exists
                var keyUpIndex = -1
                for i in index+1..<keySequence.count {
                    if !keySequence[i].isPressed && keySequence[i].keyCode == currentKey.keyCode {
                        keyUpIndex = i
                        break
                    }
                }
                
                // Create AppleScript to press this key
                let keyChar = keyToAppleScriptChar(currentKey)
                let modifiers = modifiersToAppleScript(currentKey.modifiers)
                let script = """
                tell application "System Events"
                    keystroke \(keyChar) \(modifiers)
                end tell
                """
                
                if !runAppleScript(script) {
                    success = false
                    logger.error("Failed to execute AppleScript for key: \(currentKey.displayText)")
                } else {
                    if isDebugging {
                        logger.info("✓ Successfully executed AppleScript for key: \(currentKey.displayText)")
                    }
                }
                
                // Skip to after the key up
                if keyUpIndex != -1 {
                    index = keyUpIndex + 1
                } else {
                    index += 1
                }
            } else {
                index += 1
            }
        }
        
        return success
    }
    
    // Method 3: Last resort approach for maximum compatibility
    private func executeLastResortMethod(_ macro: Macro) {
        // Process only the DOWN events and synthesize them in a simpler way
        let downEvents = macro.keySequence.filter { $0.isPressed }
        
        for key in downEvents {
            // Create a simple event using NSEvent and post it
            let keyChar = keyToChar(key.keyCode)
            
            DispatchQueue.main.async {
                // Create a key down event
                if let keyDownEvent = NSEvent.keyEvent(
                    with: .keyDown,
                    location: NSEvent.mouseLocation,
                    modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(key.modifiers)),
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: NSApp.mainWindow?.windowNumber ?? 0,
                    context: nil,
                    characters: keyChar,
                    charactersIgnoringModifiers: keyChar,
                    isARepeat: false,
                    keyCode: UInt16(key.keyCode)
                ) {
                    // Try multiple approaches to get the event to fire
                    NSApp.postEvent(keyDownEvent, atStart: false)
                    NSApp.sendEvent(keyDownEvent)
                    
                    // Create corresponding key up event
                    if let keyUpEvent = NSEvent.keyEvent(
                        with: .keyUp,
                        location: NSEvent.mouseLocation,
                        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(key.modifiers)),
                        timestamp: ProcessInfo.processInfo.systemUptime + 0.1,
                        windowNumber: NSApp.mainWindow?.windowNumber ?? 0,
                        context: nil,
                        characters: keyChar,
                        charactersIgnoringModifiers: keyChar,
                        isARepeat: false,
                        keyCode: UInt16(key.keyCode)
                    ) {
                        // Small delay between down and up
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            NSApp.postEvent(keyUpEvent, atStart: false)
                            NSApp.sendEvent(keyUpEvent)
            }
        }
                }
            }
            
            // Add a delay between keys
            usleep(100000) // 100ms
        }
    }
    
    // Helper to convert key codes to characters for AppleScript
    private func keyToAppleScriptChar(_ key: MacroKey) -> String {
        switch key.keyCode {
        case 0: return "\"a\""
        case 1: return "\"s\""
        case 2: return "\"d\""
        case 3: return "\"f\""
        case 4: return "\"h\""
        case 5: return "\"g\""
        case 6: return "\"z\""
        case 7: return "\"x\""
        case 8: return "\"c\""
        case 9: return "\"v\""
        case 11: return "\"b\""
        case 12: return "\"q\""
        case 13: return "\"w\""
        case 14: return "\"e\""
        case 15: return "\"r\""
        case 16: return "\"y\""
        case 17: return "\"t\""
        case 18: return "\"1\""
        case 19: return "\"2\""
        case 20: return "\"3\""
        case 21: return "\"4\""
        case 22: return "\"6\""
        case 23: return "\"5\""
        case 24: return "\"=\""
        case 25: return "\"9\""
        case 26: return "\"7\""
        case 27: return "\"-\""
        case 28: return "\"8\""
        case 29: return "\"0\""
        case 30: return "\"]\""
        case 31: return "\"o\""
        case 32: return "\"u\""
        case 33: return "\"[\""
        case 34: return "\"i\""
        case 35: return "\"p\""
        case 36: return "return"
        case 37: return "\"l\""
        case 38: return "\"j\""
        case 39: return "\"'\""
        case 40: return "\"k\""
        case 41: return "\";\""
        case 42: return "\"\\\\\""
        case 43: return "\",\""
        case 44: return "\"/\""
        case 45: return "\"n\""
        case 46: return "\"m\""
        case 47: return "\".\""
        case 48: return "tab"
        case 49: return "space"
        case 51: return "delete"
        case 53: return "escape"
        case 123: return "left arrow"
        case 124: return "right arrow"
        case 125: return "down arrow"
        case 126: return "up arrow"
        default: return "space" // Default to space for unknown keys
        }
    }
    
    // Helper to convert key codes to characters for NSEvents
    private func keyToChar(_ keyCode: Int) -> String {
        switch keyCode {
        case 0: return "a"
        case 1: return "s"
        case 2: return "d"
        case 3: return "f"
        case 4: return "h"
        case 5: return "g"
        case 6: return "z"
        case 7: return "x"
        case 8: return "c"
        case 9: return "v"
        case 11: return "b"
        case 12: return "q"
        case 13: return "w"
        case 14: return "e"
        case 15: return "r"
        case 16: return "y"
        case 17: return "t"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "o"
        case 32: return "u"
        case 33: return "["
        case 34: return "i"
        case 35: return "p"
        case 36: return "\r"
        case 37: return "l"
        case 38: return "j"
        case 39: return "'"
        case 40: return "k"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "n"
        case 46: return "m"
        case 47: return "."
        case 48: return "\t"
        case 49: return " "
        case 51: return "\u{8}" // delete/backspace
        case 53: return "\u{1B}" // escape
        case 123: return "\u{1C}" // left arrow
        case 124: return "\u{1D}" // right arrow
        case 125: return "\u{1F}" // down arrow
        case 126: return "\u{1E}" // up arrow
        default: return " " // Default to space for unknown keys
        }
    }
    
    // Helper to convert modifiers to AppleScript syntax
    private func modifiersToAppleScript(_ modifiers: Int) -> String {
        var parts: [String] = []
        
        if modifiers & 1 != 0 { parts.append("using {shift down}") }
        if modifiers & 2 != 0 { parts.append("using {control down}") }
        if modifiers & 4 != 0 { parts.append("using {option down}") }
        if modifiers & 8 != 0 { parts.append("using {command down}") }
        
        return parts.joined(separator: " ")
    }
    
    // Helper to run AppleScript
    private func runAppleScript(_ script: String) -> Bool {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if error != nil {
                logger.error("AppleScript error: \(error?.description ?? "unknown error")")
                return false
            }
            return true
        }
        return false
    }
    
    // Helper method to execute a key down
    private func executeKeyDown(_ key: MacroKey, forceExecution: Bool) throws {
        if key.type == .keyboard {
            // Create a CGEvent for key down
            guard let keyDownEvent = CGEvent(keyboardEventSource: CGEventSource(stateID: .combinedSessionState), 
                                            virtualKey: CGKeyCode(key.keyCode), 
                                            keyDown: true) else {
                print("   ❌ Failed to create key down event")
                throw MacroError.keyEventCreationFailed
            }
            
            // Add modifiers if any
            if key.modifiers != 0 {
                var flags = CGEventFlags()
                if key.modifiers & 1 != 0 { flags.insert(.maskShift) }
                if key.modifiers & 2 != 0 { flags.insert(.maskControl) }
                if key.modifiers & 4 != 0 { flags.insert(.maskAlternate) }
                if key.modifiers & 8 != 0 { flags.insert(.maskCommand) }
                keyDownEvent.flags = flags
            }
            
            // Post the key down event
            print("   - Posting keyDown event")
            
            // For sandboxed apps, we need to try multiple approaches
            
            // 1. Try to post to the event tap (requires accessibility permissions)
            keyDownEvent.post(tap: .cghidEventTap)
            
            // 2. Also try to use NSEvent to generate a global event
            if forceExecution {
                DispatchQueue.main.async {
                    // Create a fallback NSEvent for global delivery
                    if let keyDownNSEvent = NSEvent.keyEvent(
                        with: .keyDown,
                        location: NSPoint(x: 0, y: 0),
                        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(key.modifiers)),
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: 0,
                        context: nil,
                        characters: "",
                        charactersIgnoringModifiers: "",
                        isARepeat: false,
                        keyCode: UInt16(key.keyCode)
                    ) {
                        NSApp.postEvent(keyDownNSEvent, atStart: true)
                        print("   - Also posted NSEvent keyDown")
                    }
                }
            }
            
        } else if key.type == .mouse && forceExecution {
            // Handle mouse events if needed
            let point = CGPoint(x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y)
            print("   - Posting mouse down event at position: \(point.x), \(point.y)")
            
            switch key.keyCode {
            case 0: // Left click
                guard let mouseDownEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) else {
                    throw MacroError.mouseEventCreationFailed
                }
                mouseDownEvent.post(tap: .cghidEventTap)
                
            case 1: // Right click
                guard let mouseDownEvent = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right) else {
                    throw MacroError.mouseEventCreationFailed
                }
                mouseDownEvent.post(tap: .cghidEventTap)
                
            case 2: // Middle click
                guard let mouseDownEvent = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: point, mouseButton: .center) else {
                    throw MacroError.mouseEventCreationFailed
                }
                mouseDownEvent.post(tap: .cghidEventTap)
                
            default:
                print("   ❌ Unsupported mouse button: \(key.keyCode)")
                throw MacroError.unsupportedMouseButton
            }
        }
    }
    
    // Helper method to execute a key up
    private func executeKeyUp(_ key: MacroKey, forceExecution: Bool) throws {
        if key.type == .keyboard {
            // Create and post the key up event
            guard let keyUpEvent = CGEvent(keyboardEventSource: CGEventSource(stateID: .combinedSessionState), 
                                          virtualKey: CGKeyCode(key.keyCode), 
                                          keyDown: false) else {
                print("   ❌ Failed to create key up event")
                throw MacroError.keyEventCreationFailed
            }
            
            if key.modifiers != 0 {
                var flags = CGEventFlags()
                if key.modifiers & 1 != 0 { flags.insert(.maskShift) }
                if key.modifiers & 2 != 0 { flags.insert(.maskControl) }
                if key.modifiers & 4 != 0 { flags.insert(.maskAlternate) }
                if key.modifiers & 8 != 0 { flags.insert(.maskCommand) }
                keyUpEvent.flags = flags
            }
            print("   - Posting keyUp event")
            
            // For sandboxed apps, we need to try multiple approaches
            
            // 1. Try to post to the event tap (requires accessibility permissions)
            keyUpEvent.post(tap: .cghidEventTap)
            
            // 2. Also try to use NSEvent to generate a global event
            if forceExecution {
                DispatchQueue.main.async {
                    // Create a fallback NSEvent for global delivery
                    if let keyUpNSEvent = NSEvent.keyEvent(
                        with: .keyUp,
                        location: NSPoint(x: 0, y: 0),
                        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(key.modifiers)),
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: 0,
                        context: nil,
                        characters: "",
                        charactersIgnoringModifiers: "",
                        isARepeat: false,
                        keyCode: UInt16(key.keyCode)
                    ) {
                        NSApp.postEvent(keyUpNSEvent, atStart: true)
                        print("   - Also posted NSEvent keyUp")
                    }
                }
            }
            
        } else if key.type == .mouse && forceExecution {
            // Handle mouse events if needed
            let point = CGPoint(x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y)
            print("   - Posting mouse up event at position: \(point.x), \(point.y)")
            
            switch key.keyCode {
            case 0: // Left click
                guard let mouseUpEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
                    throw MacroError.mouseEventCreationFailed
                }
                mouseUpEvent.post(tap: .cghidEventTap)
                
            case 1: // Right click
                guard let mouseUpEvent = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right) else {
                    throw MacroError.mouseEventCreationFailed
                }
                mouseUpEvent.post(tap: .cghidEventTap)
                
            case 2: // Middle click
                guard let mouseUpEvent = CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp, mouseCursorPosition: point, mouseButton: .center) else {
                    throw MacroError.mouseEventCreationFailed
                }
                mouseUpEvent.post(tap: .cghidEventTap)
                
            default:
                print("   ❌ Unsupported mouse button: \(key.keyCode)")
                throw MacroError.unsupportedMouseButton
            }
        }
    }
    
    // Mark permission banner as shown
    func markPermissionBannerAsShown() {
        hasShownPermissionBanner = true
    }
    
    // MARK: - Private Methods
    
    private func startMonitoring() {
        // If already have permission, set up monitors
        if permissionGranted {
            setupGlobalMonitors()
        } else {
            // Otherwise try checking again
            checkInputMonitoringPermission(tryPrompt: false)
            if permissionGranted {
                setupGlobalMonitors()
            }
        }
    }
    
    private func setupGlobalMonitors() {
        if keyMonitor == nil {
            // Set up keyboard monitoring using NSEvent
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                self?.handleKeyEvent(event)
            }
        }
        
        if mouseMonitor == nil {
            // Set up mouse monitoring using NSEvent
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]) { [weak self] event in
                self?.handleMouseEvent(event)
            }
        }
        
        if flagsMonitor == nil {
            // Set up monitoring for modifier keys
            flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
                self?.handleFlagsChanged(event)
            }
        }
        
        // If any monitor was created successfully, we have permission
        if keyMonitor != nil || mouseMonitor != nil || flagsMonitor != nil {
            permissionGranted = true
            hasShownPermissionBanner = true
        }
    }
    
    private func stopMonitoring() {
        if let keyMonitor = keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        
        if let mouseMonitor = mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        
        if let flagsMonitor = flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
    }
    
    // Handle any key event - for both recording and trigger detection
    private func handleKeyEvent(_ event: NSEvent) {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.rawValue
        let isKeyDown = event.type == .keyDown
        
        let macroKey = MacroKey(type: .keyboard, keyCode: Int(keyCode), modifiers: Int(modifiers), isPressed: isKeyDown)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Log key event in debug mode
            if self.isDebugging {
                self.logger.info("🔑 Key \(isKeyDown ? "DOWN" : "UP"): \(macroKey.displayText) (code: \(keyCode))")
            }
            
            // Always record the key event during recording, including key up events
                if self.isRecording {
                // Log that we're adding this key to the recorded sequence
                if self.isDebugging {
                    self.logger.info("📝 Recording: \(macroKey.displayText) (\(isKeyDown ? "DOWN" : "UP"))")
                }
                
                    self.recordedKeys.append(macroKey)
                    
                    // Call the callback if it exists
                    self.onKeyRecordedCallback?(macroKey)
            } else if isKeyDown {
                // Only check for trigger on key down events
                    self.checkForTrigger(macroKey)
                }
                
            if isKeyDown {
                // Only add if it doesn't already exist
                if !self.currentlyPressedKeys.contains(where: { $0.keyCode == macroKey.keyCode && $0.type == .keyboard }) {
                    self.currentlyPressedKeys.append(macroKey)
                }
                self.lastPressedKey = macroKey
            } else {
                self.currentlyPressedKeys.removeAll { $0.keyCode == macroKey.keyCode && $0.type == .keyboard }
            }
        }
    }
    
    // Check if the pressed key matches any macro bindings
    private func checkForTrigger(_ key: MacroKey) {
        // Don't check for triggers during recording or when executing another macro
        if isRecording || isExecutingMacro { return }
        
        // Look for a matching trigger in our macros
        for macro in macros {
            if let boundTo = macro.boundTo, 
               boundTo.type == key.type && 
               boundTo.keyCode == key.keyCode {
                
                // Also check modifiers if they exist
                let modifiersMatch = boundTo.modifiers == 0 || boundTo.modifiers == key.modifiers
                
                if modifiersMatch {
                    // Log when a trigger is matched in debug mode
                    if isDebugging {
                        logger.info("🔥 TRIGGER DETECTED - Key: \(key.displayText) matches macro: \(macro.name)")
                    }
                    
                    print("🔥 TRIGGER DETECTED - Executing macro: \(macro.name)")
                    
                    // Execute the macro when triggered
                    executeMacro(macro, forceExecution: true)
                    
                    // Only trigger one macro per key press
                    break
                }
            }
        }
    }
    
    // Handle mouse events
    private func handleMouseEvent(_ event: NSEvent) {
        let buttonNumber = event.buttonNumber
        let isMouseDown = [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
        
        // Create a unique identifier for the mouse event to avoid duplicate entries
        let macroKey = MacroKey(type: .mouse, keyCode: Int(buttonNumber), modifiers: Int(event.modifierFlags.rawValue), isPressed: isMouseDown)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Log mouse event in debug mode
            if self.isDebugging {
                self.logger.info("🖱️ Mouse \(isMouseDown ? "DOWN" : "UP"): Button \(buttonNumber)")
            }
            
            // Always record mouse events (both down and up) during recording
                if self.isRecording {
                        self.recordedKeys.append(macroKey)
                        self.onKeyRecordedCallback?(macroKey)
            } else if isMouseDown {
                // Only check for trigger on mouse down events
                    self.checkForTrigger(macroKey)
                }
                
            if isMouseDown {
                // Add the pressed key to the current state
                // Make sure to remove any existing entry for this button first
                self.currentlyPressedKeys.removeAll { $0.keyCode == macroKey.keyCode && $0.type == .mouse }
                self.currentlyPressedKeys.append(macroKey)
                self.lastPressedKey = macroKey
            } else {
                // Remove the key from pressed keys when released
                self.currentlyPressedKeys.removeAll { $0.keyCode == macroKey.keyCode && $0.type == .mouse }
            }
        }
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        let modifierFlags = event.modifierFlags
        
        // Create an array to track which modifiers changed
        var changedModifiers: [(keyCode: Int, isPressed: Bool)] = []
        
        // Check if shift changed
        if modifierFlags.contains(.shift) != previousModifiers.contains(.shift) {
            changedModifiers.append((56, modifierFlags.contains(.shift)))
        }
        
        // Check if control changed
        if modifierFlags.contains(.control) != previousModifiers.contains(.control) {
            changedModifiers.append((59, modifierFlags.contains(.control)))
        }
        
        // Check if option/alt changed
        if modifierFlags.contains(.option) != previousModifiers.contains(.option) {
            changedModifiers.append((58, modifierFlags.contains(.option)))
        }
        
        // Check if command changed
        if modifierFlags.contains(.command) != previousModifiers.contains(.command) {
            changedModifiers.append((55, modifierFlags.contains(.command)))
        }
        
        // Check if function key changed
        if modifierFlags.contains(.function) != previousModifiers.contains(.function) {
            changedModifiers.append((63, modifierFlags.contains(.function)))
        }
        
        // Check if caps lock changed
        if modifierFlags.contains(.capsLock) != previousModifiers.contains(.capsLock) {
            changedModifiers.append((57, modifierFlags.contains(.capsLock)))
        }
        
        // Update the current modifiers
        previousModifiers = modifierFlags
        
        // Process each changed modifier
        for (keyCode, isPressed) in changedModifiers {
            let macroKey = MacroKey(type: .keyboard, keyCode: keyCode, modifiers: 0, isPressed: isPressed)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // Log modifier key event in debug mode
                if self.isDebugging {
                    self.logger.info("⌨️ Modifier \(isPressed ? "DOWN" : "UP"): \(macroKey.displayText)")
                }
                
                // Always record modifier events during recording, both down and up
                    if self.isRecording {
                        self.recordedKeys.append(macroKey)
                        
                        // Call the callback if it exists
                        self.onKeyRecordedCallback?(macroKey)
                    }
                    
                if isPressed {
                    // Only add if it doesn't already exist
                    if !self.currentlyPressedKeys.contains(where: { $0.keyCode == macroKey.keyCode && $0.type == .keyboard }) {
                        self.currentlyPressedKeys.append(macroKey)
                    }
                    self.lastPressedKey = macroKey
                } else {
                    self.currentlyPressedKeys.removeAll { $0.keyCode == macroKey.keyCode && $0.type == .keyboard }
                }
            }
        }
    }
    
    // Error types for macro execution
    enum MacroError: Error {
        case keyEventCreationFailed
        case mouseEventCreationFailed
        case unsupportedMouseButton
    }
} 
