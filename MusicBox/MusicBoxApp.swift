//
//  MusicBoxApp.swift
//  MusicBox
//
//  Created by Alex Yoon on 8/31/24.
//

import SwiftUI

@main
struct MusicBoxApp: App {
    @StateObject private var libraryViewModel = AudioLibraryViewModel()
    @State private var isShowingPreferences = false
    
    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(libraryViewModel)
        }
        .commands {
            CommandMenu("File") {
                Button("Scan Folder for New Files") {
                    Task {
                        await libraryViewModel.scanFolder()
                    }
                }
            }
            
            CommandGroup(after: .appSettings) {
                Button("Preferences") {
                    isShowingPreferences = true
                }
            }
        }
        
        Window("Preferences", id: "preferences") {
            PreferencesView(viewModel: libraryViewModel)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .defaultSize(width: 300, height: 150)
    }
}
