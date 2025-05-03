import SwiftUI

struct RecordingView: View {
    var controller: MacroController
    var onSaveMacro: (Macro?) -> Void
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "record.circle")
                    .foregroundColor(.red)
                    .font(.system(size: 24))
                
                Text("Recording: \(controller.currentMacroName)")
                    .font(.headline)
                    .foregroundColor(.red)
                
                Spacer()
                
                Text("\(controller.recordedKeys.count) keys recorded")
                    .font(.caption)
                
                Button("Stop Recording") {
                    let savedMacro = controller.stopRecording()
                    onSaveMacro(savedMacro)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            
            if !controller.recordedKeys.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(Array(controller.recordedKeys.enumerated()), id: \.offset) { index, key in
                            Text(key.displayText)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(key.isPressed ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("Press keys to record...")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }
} 