//
//  PreferencesView.swift
//  MusicBox
//
//  Created by Alex Yoon on 8/31/24.
//

import SwiftUI

struct PreferencesView: View {
    @ObservedObject var viewModel: AudioLibraryViewModel
    @State private var isShowingFolderPicker = false
    @State private var errorMessage: String?
    
    var body: some View {
        Form {
            Section(header: Text("Music Folder")) {
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
        .frame(width: 400, height: 150)
        .fileImporter(
            isPresented: $isShowingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
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
        .alert(item: Binding(
            get: { errorMessage.map { ErrorMessage(content: $0) } },
            set: { errorMessage = $0?.content }
        )) { error in
            Alert(title: Text("Error"), message: Text(error.content), dismissButton: .default(Text("OK")))
        }
    }
}
