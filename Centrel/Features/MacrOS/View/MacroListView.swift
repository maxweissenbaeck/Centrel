import SwiftUI
import SwiftData

struct MacroListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Macro.createdAt, order: .reverse) private var macros: [Macro]
    @State private var controller = MacroController()
    
    @State private var showPermissionBanner = false
    @State private var refreshTrigger = false // Trigger for refreshing the UI
    @State private var newMacroID: UUID? = nil // Track newly created macro for editing
    
    var body: some View {
        VStack(spacing: 0) {
            // Hidden view that captures global keystrokes
            GlobalKeyCaptureView(controller: controller)
                .frame(width: 0, height: 0)
            
            // Header with app title and controls
            HStack {
                Text("MacrOS")
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    createNewMacro()
                }) {
                    Label("New Macro", systemImage: "plus")
                }
                
                Button(action: {
                    controller.toggleDebugging()
                }) {
                    Label("Debug Mode", systemImage: "ladybug")
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.isDebugging ? .green : .gray)
            }
            .padding()
            
            // Permission banner
            if !controller.permissionGranted && !controller.hasShownPermissionBanner && (controller.isDebugging || controller.isRecording) {
                PermissionBannerView(controller: controller, isVisible: $showPermissionBanner)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.2)))
                    .padding(.horizontal)
                    .onAppear {
                        showPermissionBanner = true
                    }
            }
            
            // Error message display
            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
                    .padding(.horizontal)
            }
            
            // Debug key display
            if controller.isDebugging {
                DebugKeyDisplayView(controller: controller)
                    .frame(height: 100)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.windowBackgroundColor)))
                    .padding(.horizontal)
            }
            
            // Recording view
            if controller.isRecording {
                RecordingView(controller: controller) { macro in
                    if let macro = macro {
                        modelContext.insert(macro)
                        try? modelContext.save()
                        refreshTrigger.toggle()
                    }
                }
                .frame(height: 100)
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
                .padding(.horizontal)
            }
            
            // Macro list table header
            HStack(spacing: 16) {
                Text("Macro Name")
                    .font(.headline)
                    .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                
                Text("Key Sequence")
                    .font(.headline)
                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                
                Text("Binding")
                    .font(.headline)
                    .frame(width: 120, alignment: .leading)
                
                Text("Actions")
                    .font(.headline)
                    .frame(width: 80, alignment: .center)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.windowBackgroundColor).opacity(0.8))
            
            // Divider between header and content
            Divider()
            
            // Macro list
            ScrollView {
                VStack(spacing: 0) {
                    if macros.isEmpty {
                        Text("No macros recorded yet. Press the + button to create a new macro.")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(macros) { macro in
                            MacroRowView(
                                macro: macro, 
                                controller: controller,
                                isEditingName: macro.id == newMacroID,
                                onEditComplete: {
                                    // Clear the editing state when done editing
                                    newMacroID = nil
                                }
                            ) { _ in
                                // This handler is no longer needed but kept for compatibility
                            }
                            
                            Divider()
                        }
                    }
                }
                .id(refreshTrigger)
            }
        }
        .onAppear {
            // Set the model context when the view appears
            controller.setModelContext(modelContext)
        }
        .onChange(of: modelContext) { oldValue, newValue in
            // Update the controller if the model context changes
            controller.setModelContext(newValue)
        }
    }
    
    private func createNewMacro() {
        // Create a new macro with default name
        let newMacro = Macro(name: "New Macro", keySequence: [])
        
        // Save the ID to trigger editing mode
        newMacroID = newMacro.id
        
        // Add to database
        modelContext.insert(newMacro)
        try? modelContext.save()
        
        // Update the UI
        refreshTrigger.toggle()
        
        // Scroll to the new macro (would need to implement scrolling)
    }
}

struct PermissionBannerView: View {
    var controller: MacroController
    @Binding var isVisible: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading) {
                Text("Input Monitoring Permission Required")
                    .font(.headline)
                
                Text("MacrOS needs permission to monitor keyboard and mouse input. Please grant access in System Settings → Privacy & Security → Input Monitoring.")
                    .font(.caption)
            }
            
            Spacer()
            
            VStack {
                Button("Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }
                .buttonStyle(.borderedProminent)
                
                Button("Dismiss") {
                    controller.markPermissionBannerAsShown()
                    isVisible = false
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut, value: isVisible)
    }
}

struct NewMacroSheet: View {
    var controller: MacroController
    @Binding var isPresented: Bool
    @State private var macroName = ""
    
    var body: some View {
        VStack {
            Text("Create New Macro")
                .font(.headline)
                .padding()
            
            TextField("Macro Name", text: $macroName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                
                Button("Start Recording") {
                    guard !macroName.isEmpty else { return }
                    controller.startRecording(macroName: macroName)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(macroName.isEmpty)
            }
            .padding()
        }
        .frame(width: 400)
        .padding()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Macro.self, configurations: config)
    
    // Add sample data
    let macro1 = Macro(name: "Copy-Paste", keySequence: [
        MacroKey(type: .keyboard, keyCode: 8, modifiers: 8),  // Cmd+C
        MacroKey(type: .keyboard, keyCode: 9, modifiers: 8)   // Cmd+V
    ])
    container.mainContext.insert(macro1)
    
    return MacroListView()
        .modelContainer(container)
} 