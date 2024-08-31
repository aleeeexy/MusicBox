//
//  LibraryView.swift
//  MusicBox
//
//  Created by Alex Yoon on 8/31/24.
//

import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel = AudioLibraryViewModel()
    @State private var isShowingFilePicker = false
    @State private var errorMessage: ErrorMessage?
    
    var body: some View {
        VStack {
            NavigationView {
                List(viewModel.albumArtists) { artist in
                    NavigationLink(destination: AlbumListView(viewModel: viewModel, artist: artist)) {
                        Text(artist.name)
                    }
                }
                .listStyle(SidebarListStyle())
                .frame(minWidth: 200)
                
                Text("Select an artist")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 600, minHeight: 400)
            
            PlaybackControlsView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.loadMusicFolder()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { isShowingFilePicker = true }) {
                    Label("Add Files", systemImage: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            do {
                let selectedFiles = try result.get()
                viewModel.addFilesToLibrary(urls: selectedFiles)
            } catch {
                errorMessage = ErrorMessage(content: "Error selecting files: \(error.localizedDescription)")
            }
        }
        .alert(item: $errorMessage) { message in
            Alert(title: Text("Error"), message: Text(message.content), dismissButton: .default(Text("OK")))
        }
    }
}

struct AlbumListView: View {
    @ObservedObject var viewModel: AudioLibraryViewModel
    let artist: AlbumArtist
    
    var body: some View {
        List(artist.albums) { album in
            AlbumView(viewModel: viewModel, album: album)
        }
        .navigationTitle(artist.name)
    }
}

struct AlbumView: View {
    @ObservedObject var viewModel: AudioLibraryViewModel
    let album: Album
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if let artwork = album.artwork {
                    artwork
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .cornerRadius(8)
                } else {
                    Image(systemName: "music.note")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.gray)
                        .cornerRadius(8)
                }
                
                VStack(alignment: .leading) {
                    Text(album.title).font(.headline)
                    Text("\(album.year) · \(album.genre)").font(.subheadline)
                }
            }
            
            ForEach(album.tracks) { track in
                HStack {
                    Text("\(track.trackNumber)")
                    Text(track.title)
                    Spacer()
                    Text(formatDuration(track.duration))
                }
                .onTapGesture {
                    viewModel.play(track)
                    viewModel.selectedAlbum = album
                }
                .background(viewModel.currentTrack?.id == track.id ? Color.blue.opacity(0.3) : Color.clear)
            }
        }
        .padding()
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct PlaybackControlsView: View {
    @ObservedObject var viewModel: AudioLibraryViewModel
    
    var body: some View {
        VStack {
            HStack {
                Text(viewModel.currentTrack?.title ?? "No track selected")
                    .font(.headline)
                Spacer()
            }
            HStack {
                Button(action: viewModel.previousTrack) {
                    Image(systemName: "backward.fill")
                }
                Button(action: viewModel.togglePlayPause) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                }
                Button(action: viewModel.nextTrack) {
                    Image(systemName: "forward.fill")
                }
                Slider(value: $viewModel.currentTime, in: 0...viewModel.duration) { editing in
                    if !editing {
                        viewModel.seek(to: viewModel.currentTime)
                    }
                }
                Text(formatDuration(viewModel.currentTime))
                Text(formatDuration(viewModel.duration))
            }
            .padding()
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct ErrorMessage: Identifiable {
    let id = UUID()
    let content: String
}
