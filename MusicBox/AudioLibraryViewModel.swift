import Foundation
import AVFoundation
import ID3TagEditor
import SwiftUI
import Combine

@MainActor
class AudioLibraryViewModel: ObservableObject {
    @Published var musicFolderURL: URL? {
        didSet {
            if let url = musicFolderURL {
                saveMusicFolderURL(url)
            }
        }
    }
    @Published var albumArtists: [AlbumArtist] = []
    @Published var isScanning = false
    @Published var scanProgress: Float = 0
    @Published var scannedFiles: Int = 0
    @Published var totalFiles: Int = 0
    @Published var selectedAlbumArtist: AlbumArtist?
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
    @Published var selectedAlbum: Album?
    
    
    private let fileManager = FileManager.default
    private let id3TagEditor = ID3TagEditor()
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var processedFiles: Set<String> = []
    
    init() {
        loadMusicFolder()
        loadLibrary()
    }
    
    private func saveMusicFolderURL(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: "musicFolderURL")
    }
    
    func loadMusicFolder() {
        if let savedURLString = UserDefaults.standard.string(forKey: "musicFolderURL") {
            musicFolderURL = URL(fileURLWithPath: savedURLString)
        }
    }
    
    private func loadLibrary() {
        if let data = UserDefaults.standard.data(forKey: "libraryData"),
           let decodedLibrary = try? JSONDecoder().decode([AlbumArtist].self, from: data) {
            self.albumArtists = decodedLibrary
        }
    }
    
    private func saveLibrary() {
        if let encodedData = try? JSONEncoder().encode(albumArtists) {
            UserDefaults.standard.set(encodedData, forKey: "libraryData")
        }
    }
    
    func scanFolder() async {
        guard let folderURL = musicFolderURL else { return }
        
        isScanning = true
        scanProgress = 0
        scannedFiles = 0
        totalFiles = 0
        
        do {
            var existingFiles = Set(getAllTrackURLs())
            var newFiles = Set<URL>()
            
            totalFiles = try await countMP3Files(in: folderURL)
            try await scanFolderRecursively(folderURL, existingFiles: &existingFiles, newFiles: &newFiles)
            
            // Remove tracks that no longer exist
            removeNonexistentTracks(existingFiles)
            
            // Add new tracks
            for fileURL in newFiles {
                await processAudioFile(fileURL)
            }
            
            organizeLibrary()
            saveLibrary()
            
            objectWillChange.send()
        } catch {
            print("Error scanning folder: \(error.localizedDescription)")
        }
        
        isScanning = false
    }

    private func scanFolderRecursively(_ folderURL: URL, existingFiles: inout Set<URL>, newFiles: inout Set<URL>) async throws {
        let fileURLs = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey])
        
        for fileURL in fileURLs {
            let isDirectory = try fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            
            if isDirectory {
                try await scanFolderRecursively(fileURL, existingFiles: &existingFiles, newFiles: &newFiles)
            } else if fileURL.pathExtension.lowercased() == "mp3" {
                if existingFiles.contains(fileURL) {
                    existingFiles.remove(fileURL)
                } else {
                    newFiles.insert(fileURL)
                }
                scannedFiles += 1
                scanProgress = Float(scannedFiles) / Float(totalFiles)
            }
        }
    }

    
    private func getAllTrackURLs() -> [URL] {
        return albumArtists.flatMap { artist in
            artist.albums.flatMap { album in
                album.tracks.map { $0.url }
            }
        }
    }
    
    private func removeNonexistentTracks(_ nonexistentURLs: Set<URL>) {
        for artistIndex in albumArtists.indices {
            for albumIndex in albumArtists[artistIndex].albums.indices {
                albumArtists[artistIndex].albums[albumIndex].tracks.removeAll { track in
                    nonexistentURLs.contains(track.url)
                }
            }
            // Remove empty albums
            albumArtists[artistIndex].albums.removeAll { $0.tracks.isEmpty }
        }
        // Remove empty artists
        albumArtists.removeAll { $0.albums.isEmpty }
    }

    func setMusicFolder(_ url: URL) {
        musicFolderURL = url
        Task {
            await scanFolder()
        }
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
        let filePath = url.path
        
        // Check if the file has already been processed
        if processedFiles.contains(filePath) {
            return
        }
        
        do {
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
            
            let track = Track(url: url, title: title, artist: albumArtist, trackNumber: trackPosition, duration: duration)
            
            updateLibrary(albumArtist: albumArtist, album: album, year: year, genre: genre, track: track, artwork: artwork)
            
            // Mark the file as processed
            processedFiles.insert(filePath)
        } catch {
            print("Error processing audio file: \(error.localizedDescription)")
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
                if !albumArtists[existingArtistIndex].albums[existingAlbumIndex].tracks.contains(where: { $0.url == track.url }) {
                    albumArtists[existingArtistIndex].albums[existingAlbumIndex].tracks.append(track)
                }
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
        Task {
            selectedAlbum = await findAlbumForTrack(track)
        }
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
            
            // Use a continuation to handle the async call
            Task {
                let duration = try await playerItem.asset.load(.duration)
                await MainActor.run {
                    self.duration = duration.seconds
                }
            }
            
            player.play()
            self.isPlaying = true
            
            NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying(_:)), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            NotificationCenter.default.addObserver(self, selector: #selector(playerDidFail(_:)), name: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
            
        } catch {
            print("Error setting up audio playback: \(error)")
            isPlaying = false
        }
    }

    private func findAlbumForTrack(_ track: Track) async -> Album? {
        for artist in albumArtists {
            if let album = artist.albums.first(where: { $0.tracks.contains(where: { $0.id == track.id }) }) {
                return album
            }
        }
        return nil  // Changed 'null' to 'nil'
    }

    @objc func playerDidFinishPlaying(_ notification: Notification) {
        Task {
            await nextTrack()
        }
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
                Task {
                    selectedAlbum = await findAlbumForTrack(firstTrack)
                }
                seek(to: 0)
                player?.pause()
                isPlaying = false
            }
        }
    }
    
    func addFilesToLibrary(urls: [URL]) async {
        for url in urls where url.pathExtension.lowercased() == "mp3" {
            await processAudioFile(url)
        }
        organizeLibrary()
        objectWillChange.send()
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
    
    func seek(to time: TimeInterval) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }
        
    func previousTrack() async {
        guard let currentTrack = currentTrack,
              let currentAlbum = selectedAlbum else { return }
        
        if currentTime > 1 {
            // If more than 1 second has played, go to the start of the current track
            seek(to: 0)
        } else {
            // Go to the previous track
            if let currentIndex = currentAlbum.tracks.firstIndex(where: { $0.id == currentTrack.id }),
               currentIndex > 0 {
                await play(currentAlbum.tracks[currentIndex - 1])
            } else {
                // This is the first track, pause playback
                player?.pause()
                isPlaying = false
                seek(to: 0)
            }
        }
    }
    
    func togglePlayPause() async {
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            if let currentTrack = currentTrack {
                await play(currentTrack)
            } else if let firstTrack = queue.first {
                await play(firstTrack)
            }
        }
    }
    
    private func updateQueue(startingFrom track: Track) {
        guard let album = selectedAlbum else { return }
        if let index = album.tracks.firstIndex(where: { $0.id == track.id }) {
            queue = Array(album.tracks[index+1..<album.tracks.count])
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        Task { @MainActor in
            removeTimeObserver()
        }
    }
}

struct AlbumArtist: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    var albums: [Album]
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: AlbumArtist, rhs: AlbumArtist) -> Bool {
        lhs.id == rhs.id
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, albums
    }
    
    init(id: UUID = UUID(), name: String, albums: [Album]) {
        self.id = id
        self.name = name
        self.albums = albums
    }
}

class Album: Identifiable, ObservableObject, Codable {
    let id: UUID
    let title: String
    let year: Int
    let genre: String
    var tracks: [Track]
    let artwork: Image?
    @Published var selectedTracks: Set<UUID> = []

    enum CodingKeys: String, CodingKey {
        case id, title, year, genre, tracks, artwork
    }

    init(id: UUID = UUID(), title: String, year: Int, genre: String, tracks: [Track], artwork: Image?) {
        self.id = id
        self.title = title
        self.year = year
        self.genre = genre
        self.tracks = tracks
        self.artwork = artwork
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        year = try container.decode(Int.self, forKey: .year)
        genre = try container.decode(String.self, forKey: .genre)
        tracks = try container.decode([Track].self, forKey: .tracks)
        artwork = nil // We can't decode Image, so we'll set it to nil when decoding
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(year, forKey: .year)
        try container.encode(genre, forKey: .genre)
        try container.encode(tracks, forKey: .tracks)
        // We can't encode Image, so we'll skip it
    }
}

struct Track: Identifiable, Codable {
    let id: UUID
    let url: URL
    let title: String
    let artist: String
    let trackNumber: Int
    let duration: TimeInterval
    
    enum CodingKeys: String, CodingKey {
        case id, url, title, artist, trackNumber, duration
    }
    
    init(id: UUID = UUID(), url: URL, title: String, artist: String, trackNumber: Int, duration: TimeInterval) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.trackNumber = trackNumber
        self.duration = duration
    }
}
