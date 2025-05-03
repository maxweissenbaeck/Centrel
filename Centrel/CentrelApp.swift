//
//  CentrelApp.swift
//  Centrel
//
//  Created by Max Weißenbäck on 03.05.25.
//

import SwiftUI
import SwiftData

@main
struct CentrelApp: App {
    let modelContainer: ModelContainer = {
        let schema = Schema([Macro.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        return try! ModelContainer(for: schema, configurations: config)
    }()

    var body: some Scene {
        WindowGroup {
            MacroListView()
                .modelContainer(modelContainer)
        }
    }
}
