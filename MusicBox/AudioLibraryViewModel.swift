import Foundation
import AVFoundation
import ID3TagEditor
import SwiftUI
import Combine

@MainActor
class AudioLibraryViewModel: ObservableObject {
    @Published var musicFolderURL: URL?
    @Published var albumArtists: [AlbumArtist] = []
    @Published var selectedAlbumArtist: AlbumArtist?
    @Published var selectedAlbum: Album?
    @Published var currentTrack: Track?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = UserDefaults.standard.float(forKey: "playerVolume") {
        didSet {
            player?.volume = volume
            UserDefaults.standard.set(volume, forKey: "playerVolume")
        }
    }
    @Published var queue: [Track] = []
    @Published var isScanning = false
    @Published var scanProgress: Float = 0
    @Published var scannedFiles: Int = 0
    @Published var totalFiles: Int = 0

    private let fileManager = FileManager.default
    private let id3TagEditor = ID3TagEditor()
    private var player: AVPlayer?
    private var timeObserver: Any?

    init() {
        if UserDefaults.standard.object(forKey: "playerVolume") == nil {
            UserDefaults.standard.set(0.5, forKey: "playerVolume")
        }
        volume = UserDefaults.standard.float(forKey: "playerVolume")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        Task { @MainActor in
            removeTimeObserver()
        }
    }

    func setMusicFolder(_ url: URL) {
        musicFolderURL = url
        UserDefaults.standard.set(url.path, forKey: "MusicFolderURL")
    }

    func loadMusicFolder() {
        if let savedURLString = UserDefaults.standard.string(forKey: "MusicFolderURL") {
            musicFolderURL = URL(fileURLWithPath: savedURLString)
            Task {
                await scanFolder()
            }
        }
    }

    func scanFolder() async {
        guard let folderURL = musicFolderURL else { return }
        
        isScanning = true
        scanProgress = 0
        scannedFiles = 0
        totalFiles = 0
        
        do {
            totalFiles = try await countMP3Files(in: folderURL)
            try await scanFolderRecursively(folderURL)
            organizeLibrary()
            
            objectWillChange.send()
        } catch {
            print("Error scanning folder: \(error.localizedDescription)")
        }
        
        isScanning = false
    }
    
    private func scanFolderRecursively(_ folderURL: URL) async throws {
        let fileURLs = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey])
        
        for fileURL in fileURLs {
            let isDirectory = try fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            
            if isDirectory {
                try await scanFolderRecursively(fileURL)
            } else if fileURL.pathExtension.lowercased() == "mp3" {
                await processAudioFile(fileURL)
                scannedFiles += 1
                scanProgress = Float(scannedFiles) / Float(totalFiles)
            }
        }
    }

    private func countMP3Files(in folder: URL) async throws -> Int {
        let fileURLs = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])
        var count = 0
        
        for fileURL in fileURLs {
            let isDirectory = try fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            
            if isDirectory {
                count += try await countMP3Files(in: fileURL)
            } else if fileURL.pathExtension.lowercased() == "mp3" {
                count += 1
            }
        }
        
        return count
    }

    private func processAudioFile(_ url: URL) async {
        do {
            let filePath = url.path
            guard let id3Tag = try id3TagEditor.read(from: filePath) else { return }
            
            let albumArtist = (id3Tag.frames[.albumArtist] as? ID3FrameWithStringContent)?.content ?? "Unknown Artist"
            let album = (id3Tag.frames[.album] as? ID3FrameWithStringContent)?.content ?? "Unknown Album"
            let title = (id3Tag.frames[.title] as? ID3FrameWithStringContent)?.content ?? url.deletingPathExtension().lastPathComponent
            let trackPosition = (id3Tag.frames[.trackPosition] as? ID3FramePartOfTotal)?.part ?? 0
            let year = Int((id3Tag.frames[.recordingYear] as? ID3FrameWithStringContent)?.content ?? "0") ?? 0
            let genre = (id3Tag.frames[.genre] as? ID3FrameWithStringContent)?.content ?? "Unknown Genre"
            
            let asset = AVAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            
            let artwork = loadArtwork(from: id3Tag)
            
            let track = Track(url: url, title: title, trackNumber: trackPosition, duration: duration)
            
            updateLibrary(albumArtist: albumArtist, album: album, year: year, genre: genre, track: track, artwork: artwork)
        } catch {
            print("Error processing audio file: \(error.localizedDescription)")
        }
    }

    func addFilesToLibrary(urls: [URL]) {
        Task {
            for url in urls where url.pathExtension.lowercased() == "mp3" {
                await processAudioFile(url)
            }
            organizeLibrary()
            objectWillChange.send()
        }
    }

    private func loadArtwork(from id3Tag: ID3Tag) -> Image? {
        guard let attachedPictureFrame = id3Tag.frames[.attachedPicture(.frontCover)] as? ID3FrameAttachedPicture,
              let nsImage = NSImage(data: attachedPictureFrame.picture) else {
            return nil
        }
        return Image(nsImage: nsImage)
    }

    private func updateLibrary(albumArtist: String, album: String, year: Int, genre: String, track: Track, artwork: Image?) {
        if let existingArtistIndex = albumArtists.firstIndex(where: { $0.name == albumArtist }) {
            if let existingAlbumIndex = albumArtists[existingArtistIndex].albums.firstIndex(where: { $0.title == album }) {
                albumArtists[existingArtistIndex].albums[existingAlbumIndex].tracks.append(track)
            } else {
                let newAlbum = Album(title: album, year: year, genre: genre, tracks: [track], artwork: artwork)
                albumArtists[existingArtistIndex].albums.append(newAlbum)
            }
        } else {
            let newAlbum = Album(title: album, year: year, genre: genre, tracks: [track], artwork: artwork)
            let newArtist = AlbumArtist(name: albumArtist, albums: [newAlbum])
            albumArtists.append(newArtist)
        }
    }

    private func organizeLibrary() {
        for artistIndex in albumArtists.indices {
            albumArtists[artistIndex].albums.sort { $0.year != $1.year ? $0.year > $1.year : $0.title < $1.title }
            
            for albumIndex in albumArtists[artistIndex].albums.indices {
                albumArtists[artistIndex].albums[albumIndex].tracks.sort { $0.trackNumber < $1.trackNumber }
            }
        }
        
        albumArtists.sort { $0.name < $1.name }
    }

    func play(_ track: Track) {
        currentTrack = track
        selectedAlbum = findAlbumForTrack(track)
        updateQueue(startingFrom: track)
        
        do {
            let playerItem = AVPlayerItem(url: track.url)
            
            player?.pause()
            player?.replaceCurrentItem(with: playerItem)
            
            if player == nil {
                player = AVPlayer(playerItem: playerItem)
            }
            
            guard let player = player else {
                throw NSError(domain: "AudioPlayerError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create AVPlayer"])
            }
            
            player.volume = volume
            
            setupTimeObserver()
            
            Task {
                do {
                    let duration = try await playerItem.asset.load(.duration)
                    await MainActor.run {
                        self.duration = duration.seconds
                    }
                    
                    player.play()
                    self.isPlaying = true
                } catch {
                    print("Error loading track duration: \(error)")
                }
            }
            
            NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            NotificationCenter.default.addObserver(self, selector: #selector(playerDidFail), name: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
            
        } catch {
            print("Error setting up audio playback: \(error)")
            isPlaying = false
        }
    }

    @objc func playerDidFinishPlaying(_ notification: Notification) {
        nextTrack()
    }
    
    @objc func playerDidFail(_ notification: Notification) {
        if let playerItem = notification.object as? AVPlayerItem,
           let error = playerItem.error {
            print("Player failed with error: \(error)")
        } else {
            print("Player failed with unknown error")
        }
        isPlaying = false
    }
    
    private func setupTimeObserver() {
        removeTimeObserver()
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
    }
    
    private func removeTimeObserver() {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    func togglePlayPause() {
        isPlaying ? player?.pause() : player?.play()
        isPlaying.toggle()
    }
    
    func seek(to time: TimeInterval) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }

    func nextTrack() {
        if let nextTrack = queue.first {
            queue.removeFirst()
            play(nextTrack)
        } else {
            // No more tracks in queue, go to first track of first album and pause
            if let firstArtist = albumArtists.first,
               let firstAlbum = firstArtist.albums.first,
               let firstTrack = firstAlbum.tracks.first {
                currentTrack = firstTrack
                selectedAlbum = firstAlbum
                seek(to: 0)
                player?.pause()
                isPlaying = false
            }
        }
    }

    func previousTrack() {
        guard let currentTrack = currentTrack,
              let currentAlbum = selectedAlbum else { return }
        
        if currentTime > 1 {
            // If more than 1 second has played, go to the start of the current track
            seek(to: 0)
        } else {
            // Go to the previous track
            if let currentIndex = currentAlbum.tracks.firstIndex(where: { $0.id == currentTrack.id }),
               currentIndex > 0 {
                play(currentAlbum.tracks[currentIndex - 1])
            } else {
                // This is the first track, pause playback
                player?.pause()
                isPlaying = false
                seek(to: 0)
            }
        }
    }

    private func updateQueue(startingFrom track: Track) {
        guard let album = selectedAlbum else { return }
        if let index = album.tracks.firstIndex(where: { $0.id == track.id }) {
            queue = Array(album.tracks[index+1..<album.tracks.count])
        }
    }

    private func findAlbumForTrack(_ track: Track) -> Album? {
        for artist in albumArtists {
            if let album = artist.albums.first(where: { $0.tracks.contains(where: { $0.id == track.id }) }) {
                return album
            }
        }
        return nil
    }
}

struct AlbumArtist: Identifiable, Hashable {
    let id = UUID()
    let name: String
    var albums: [Album]
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: AlbumArtist, rhs: AlbumArtist) -> Bool {
        lhs.id == rhs.id
    }
}

class Album: Identifiable, ObservableObject {
    let id = UUID()
    let title: String
    let year: Int
    let genre: String
    var tracks: [Track]
    let artwork: Image?
    @Published var selectedTracks: Set<UUID> = []

    init(title: String, year: Int, genre: String, tracks: [Track], artwork: Image?) {
        self.title = title
        self.year = year
        self.genre = genre
        self.tracks = tracks
        self.artwork = artwork
    }
}

struct Track: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let trackNumber: Int
    let duration: TimeInterval
}
