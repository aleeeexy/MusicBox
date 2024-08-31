//
//  MusicBoxApp.swift
//  MusicBox
//
//  Created by Alex Yoon on 8/31/24.
//

import SwiftUI

@main
struct MusicBoxApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
