import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var viewModel: AudioLibraryViewModel
    @State private var isShowingFilePicker = false
    @State private var errorMessage: ErrorMessage?
    @State private var selectedArtist: AlbumArtist?
    
    let sidebarWidth: CGFloat = 200
    
    var body: some View {
        VStack {
            HStack(spacing: 0) {
                sidebar
                Divider()
                mainContent
            }
            PlaybackControlsView(viewModel: viewModel)
        }
        .frame(minWidth: 800, minHeight: 600)
        .toolbar { toolbarContent }
        .fileImporter(isPresented: $isShowingFilePicker, allowedContentTypes: [.audio], allowsMultipleSelection: true, onCompletion: handleFileImport)
        .alert(item: $errorMessage) { message in
            Alert(title: Text("Error"), message: Text(message.content), dismissButton: .default(Text("OK")))
        }
    }
    
    private var sidebar: some View {
        VStack {
            Text("Artists")
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.windowBackgroundColor))
            
            List(viewModel.albumArtists, selection: $selectedArtist) { artist in
                ArtistRowView(artist: artist, viewModel: viewModel, selectedArtist: $selectedArtist)
                    .tag(artist)
            }
            .listStyle(SidebarListStyle())
        }
        .frame(width: sidebarWidth)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var mainContent: some View {
        Group {
            if viewModel.isScanning {
                scanningView
            } else if let artist = selectedArtist {
                artistView(artist)
            } else {
                Text("Select an artist")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private var scanningView: some View {
        VStack(spacing: 20) {
            Text("Scanning for new files...")
                .font(.headline)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                    
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * CGFloat(viewModel.scanProgress))
                }
            }
            .frame(height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 40)
            
            Text("\(viewModel.scannedFiles) / \(viewModel.totalFiles)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func artistView(_ artist: AlbumArtist) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(artist.name)
                    .font(.largeTitle)
                    .padding(.horizontal)
                
                LazyVStack(spacing: 20) {
                    ForEach(artist.albums) { album in
                        AlbumModuleView(viewModel: viewModel, album: album)
                    }
                }
                .padding(.horizontal)
            }
        }
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            // Deselect all tracks when tapping on empty space
            for artist in viewModel.albumArtists {
                for album in artist.albums {
                    album.selectedTracks.removeAll()
                }
            }
        }
    }
    
    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .automatic) {
                Button(action: { isShowingFilePicker = true }) {
                    Label("Add Files", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    Task {
                        await viewModel.scanFolder()
                    }
                }) {
                    Label("Scan for New Files", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.musicFolderURL == nil || viewModel.isScanning)
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            let selectedFiles = try result.get()
            Task {
                await viewModel.addFilesToLibrary(urls: selectedFiles)
            }
        } catch {
            errorMessage = ErrorMessage(content: "Error selecting files: \(error.localizedDescription)")
        }
    }
}
struct ArtistRowView: View {
    let artist: AlbumArtist
    @ObservedObject var viewModel: AudioLibraryViewModel
    @Binding var selectedArtist: AlbumArtist?
    
    var body: some View {
        Text(artist.name)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
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
}

struct AlbumModuleView: View {
    @ObservedObject var viewModel: AudioLibraryViewModel
    @ObservedObject var album: Album
    @State private var lastSelectedTrackIndex: Int?
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            albumArtwork
            albumDetails
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(10)
    }
    
    private var albumArtwork: some View {
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
        .onTapGesture {
            album.selectedTracks = Set(album.tracks.map { $0.id })
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if let firstTrack = album.tracks.first {
                    viewModel.play(firstTrack)
                }
            }
        )
    }
    
    private var albumDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            albumTitle
            albumInfo
            trackList
        }
    }
    
    private var albumTitle: some View {
        Text(album.title)
            .font(.title2)
            .fontWeight(.bold)
            .onTapGesture {
                album.selectedTracks = Set(album.tracks.map { $0.id })
            }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    if let firstTrack = album.tracks.first {
                        viewModel.play(firstTrack)
                    }
                }
            )
    }
    
    private var albumInfo: some View {
        HStack {
            Text("\(album.year) · \(album.genre)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("Total: \(totalAlbumLength) min")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var trackList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                TrackRowView(track: track, index: index, viewModel: viewModel, album: album, lastSelectedTrackIndex: $lastSelectedTrackIndex)
            }
        }
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var totalAlbumLength: Int {
        let totalSeconds = album.tracks.reduce(0) { $0 + $1.duration }
        return Int(round(totalSeconds / 60))
    }
}

struct TrackRowView: View {
    let track: Track
    let index: Int
    @ObservedObject var viewModel: AudioLibraryViewModel
    @ObservedObject var album: Album
    @Binding var lastSelectedTrackIndex: Int?
    
    var body: some View {
        HStack {
            if isTrackPlaying(track) {
                Image(systemName: viewModel.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                    .foregroundColor(.blue)
                    .frame(width: 30, alignment: .trailing)
            } else {
                Text("\(track.trackNumber)")
                    .frame(width: 30, alignment: .trailing)
            }
            Text(track.title)
            Spacer()
            Text(formatDuration(track.duration))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isTrackSelected(track) ? Color.blue.opacity(0.3) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTrackSelection(index, track)
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                viewModel.play(track)
            }
        )
    }
    
    private func isTrackPlaying(_ track: Track) -> Bool {
        return viewModel.currentTrack?.id == track.id
    }
    
    private func isTrackSelected(_ track: Track) -> Bool {
        return album.selectedTracks.contains(track.id)
    }
    
    private func handleTrackSelection(_ index: Int, _ track: Track) {
        let modifiers = NSEvent.modifierFlags
        
        if modifiers.contains(.shift), let lastIndex = lastSelectedTrackIndex {
            let range = min(lastIndex, index)...max(lastIndex, index)
            let tracksInRange = album.tracks[range].map { $0.id }
            album.selectedTracks.formUnion(tracksInRange)
        } else if modifiers.contains(.command) {
            if album.selectedTracks.contains(track.id) {
                album.selectedTracks.remove(track.id)
            } else {
                album.selectedTracks.insert(track.id)
            }
        } else {
            album.selectedTracks = [track.id]
        }
        
        lastSelectedTrackIndex = index
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
            HStack(spacing: 10) {
                Button(action: {
                    Task {
                        await viewModel.previousTrack()
                    }
                }) {
                    Image(systemName: "backward.fill")
                }
                Button(action: {
                    Task {
                        await viewModel.togglePlayPause()
                    }
                }) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                }
                Button(action: {
                    viewModel.nextTrack()
                }) {
                    Image(systemName: "forward.fill")
                }

                Slider(value: $viewModel.currentTime, in: 0...viewModel.duration) { editing in
                    if !editing {
                        viewModel.seek(to: viewModel.currentTime)
                    }
                }
                
                Text(formatDuration(viewModel.currentTime))
                Text(formatDuration(viewModel.duration))
                
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
