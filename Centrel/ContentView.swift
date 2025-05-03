//
//  ContentView.swift
//  Centrel
//
//  Created by Max Weißenbäck on 03.05.25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        MacroListView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Macro.self)
}
