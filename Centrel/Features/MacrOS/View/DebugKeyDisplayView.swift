import SwiftUI

struct DebugKeyDisplayView: View {
    var controller: MacroController
    
    var body: some View {
        VStack(spacing: 10) {
            if let lastKey = controller.lastPressedKey {
                HStack {
                    Text("Last key: ")
                        .font(.caption)
                    
                    Text(lastKey.displayText)
                        .font(.caption.bold())
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(lastKey.isPressed ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    
                    Spacer()
                }
            } else {
                HStack {
                    Text("Last key: none")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
            HStack(alignment: .center) {
                Text("Currently pressed: ")
                    .font(.caption)
                
                // Fixed-height container that won't jump
                ZStack(alignment: .leading) {
                    if controller.currentlyPressedKeys.isEmpty {
                        Text("None")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                // Use the unique ID from MacroKey
                                ForEach(controller.currentlyPressedKeys, id: \.id) { key in
                                    Text(key.displayText)
                                        .font(.caption)
                                        .padding(6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.blue.opacity(0.2))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }
                        }
                    }
                }
                .frame(height: 32) // Fixed height to prevent jumping
                
                Spacer()
            }
            
            HStack {
                if controller.permissionGranted {
                    Label("Permission granted", systemImage: "checkmark.circle")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    HStack(spacing: 8) {
                        Label("Permission required", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                            .font(.caption)
                        
                        Button("Request Permission") {
                            controller.requestPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    }
                }
                
                Spacer()
                
                // Add button to toggle simulation for testing
                if !controller.permissionGranted {
                    Button(controller.useSimulation ? "Stop Simulation" : "Start Simulation") {
                        controller.toggleSimulation()
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .tint(controller.useSimulation ? .red : .blue)
                    .controlSize(.small)
                }
                
                Button("Log Macros") {
                    controller.logStoredMacros()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
