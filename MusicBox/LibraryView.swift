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
    @State private var selectedArtist: AlbumArtist?
    
    var body: some View {
        VStack {
            NavigationView {
                List(viewModel.albumArtists, selection: $selectedArtist) { artist in
                    Text(artist.name)
                        .tag(artist)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedArtist = artist
                        }
                        .onTapGesture(count: 2) {
                            if let firstAlbum = artist.albums.first,
                               let firstTrack = firstAlbum.tracks.first {
                                viewModel.play(firstTrack)
                            }
                        }
                }
                .listStyle(SidebarListStyle())
                .frame(minWidth: 200)
                
                if let artist = selectedArtist {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 20) {
                            ForEach(artist.albums) { album in
                                AlbumView(viewModel: viewModel, album: album)
                            }
                        }
                        .padding()
                    }
                } else {
                    Text("Select an artist")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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

struct AlbumView: View {
    @ObservedObject var viewModel: AudioLibraryViewModel
    let album: Album
    
    var body: some View {
        VStack {
            Group {
                if let artwork = album.artwork {
                    artwork
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "music.note")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 150, height: 150)
            .cornerRadius(8)
            .onTapGesture(count: 2) {
                if let firstTrack = album.tracks.first {
                    viewModel.play(firstTrack)
                }
            }
            
            Text(album.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            
            Text("\(album.year) · \(album.genre)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .contextMenu {
            ForEach(album.tracks) { track in
                Button(track.title) {
                    viewModel.play(track)
                }
            }
        }
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
            HStack(spacing: 10) {
                Button(action: viewModel.previousTrack) {
                    Image(systemName: "backward.fill")
                }
                Button(action: viewModel.togglePlayPause) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                }
                Button(action: viewModel.nextTrack) {
                    Image(systemName: "forward.fill")
                }
                
                // Progress slider
                Slider(value: $viewModel.currentTime, in: 0...viewModel.duration) { editing in
                    if !editing {
                        viewModel.seek(to: viewModel.currentTime)
                    }
                }
                
                Text(formatDuration(viewModel.currentTime))
                Text(formatDuration(viewModel.duration))
                
                // Volume control
                Image(systemName: "speaker.fill")
                    .foregroundColor(.secondary)
                Slider(value: $viewModel.volume, in: 0...1)
                    .frame(width: 80)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(.secondary)
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

struct ErrorMessage: Identifiable {
    let id = UUID()
    let content: String
}
