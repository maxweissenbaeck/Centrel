import SwiftUI
import AppKit

struct GlobalKeyCaptureView: NSViewRepresentable {
    @Environment(\.modelContext) var context
    var controller: MacroController
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            let macroKey = MacroKey(
                type: .keyboard,
                keyCode: Int(event.keyCode),
                modifiers: Int(event.modifierFlags.rawValue),
                isPressed: event.type == .keyDown
            )
            
            // If recording, add to the controller's recordedKeys
            if controller.isRecording {
                controller.recordedKeys.append(macroKey)
            }
            
            // For debugging
            if controller.isDebugging {
                DispatchQueue.main.async {
                    controller.lastPressedKey = macroKey
                    if event.type == .keyDown {
                        controller.currentlyPressedKeys.append(macroKey)
                    } else {
                        controller.currentlyPressedKeys.removeAll { 
                            $0.keyCode == macroKey.keyCode && $0.type == macroKey.type 
                        }
                    }
                }
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) { }
    
    func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator {
        var monitor: Any?
    }
} 