import SwiftUI

struct PreferencesView: View {
    @ObservedObject var viewModel: AudioLibraryViewModel
    @Binding var isPresented: Bool
    @State private var selectedSidebarItem: String? = "Library"
    
    var body: some View {
        NavigationView {
            List {
                NavigationLink(destination: LibraryPreferencesView(viewModel: viewModel), tag: "Library", selection: $selectedSidebarItem) {
                    Label("Library", systemImage: "music.note.list")
                }
                // Add more sidebar items here in the future
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 150, idealWidth: 250, maxWidth: 300)
            
            LibraryPreferencesView(viewModel: viewModel)
        }
        .navigationTitle("Preferences")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Close") {
                    isPresented = false
                }
            }
        }
    }
}

struct LibraryPreferencesView: View {
    @ObservedObject var viewModel: AudioLibraryViewModel
    @State private var isShowingFolderPicker = false
    @State private var errorMessage: String?
    
    var body: some View {
        Form {
            Section(header: Text("Music Library Folder")) {
                HStack {
                    Text(viewModel.musicFolderURL?.path ?? "No folder selected")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose Folder") {
                        isShowingFolderPicker = true
                    }
                }
            }
        }
        .padding()
        .fileImporter(
            isPresented: $isShowingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderSelection(result)
        }
        .alert(item: Binding(
            get: { errorMessage.map { ErrorMessage(content: $0) } },
            set: { errorMessage = $0?.content }
        )) { error in
            Alert(title: Text("Error"), message: Text(error.content), dismissButton: .default(Text("OK")))
        }
    }
    
    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        do {
            let selectedFolder = try result.get().first!
            viewModel.setMusicFolder(selectedFolder)
            Task {
                await viewModel.scanFolder()
            }
        } catch {
            errorMessage = "Error selecting folder: \(error.localizedDescription)"
        }
    }
}
