import SwiftUI

@main
struct MusicBoxApp: App {
    @StateObject private var libraryViewModel = AudioLibraryViewModel()
    @State private var isShowingPreferences = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                LibraryView()
                    .environmentObject(libraryViewModel)
                
                if isShowingPreferences {
                    Color.black.opacity(0.3)
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture {
                            isShowingPreferences = false
                        }
                    
                    PreferencesView(viewModel: libraryViewModel, isPresented: $isShowingPreferences)
                        .frame(width: 600, height: 400)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(10)
                        .shadow(radius: 10)
                }
            }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan Folder for New Files") {
                    Task {
                        await scanFolder()
                    }
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])
            }
            
            CommandGroup(after: .textEditing) {
                Button("Preferences...") {
                    isShowingPreferences.toggle()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
    
    private func scanFolder() async {
        await libraryViewModel.scanFolder()
    }
}
