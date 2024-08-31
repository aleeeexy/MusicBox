//
//  AudioPlayerViewModel.swift
//  MusicBox
//
//  Created by Alex Yoon on 8/31/24.
//

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
    @Published var volume: Float = 0.5
    @Published var queue: [Track] = []

    private let fileManager = FileManager.default
    private let id3TagEditor = ID3TagEditor()
    private var player: AVPlayer?
    private var timeObserver: Any?

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
    
    func addFilesToLibrary(urls: [URL]) {
        Task {
            for url in urls where url.pathExtension.lowercased() == "mp3" {
                await processAudioFile(url)
            }
            organizeLibrary()
        }
    }
    
    func scanFolder() async {
        guard let folderURL = musicFolderURL else { return }
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
            for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "mp3" {
                await processAudioFile(fileURL)
            }
            organizeLibrary()
        } catch {
            handleError(error)
        }
    }
    
    private func processAudioFile(_ url: URL) async {
        do {
            let filePath = url.path
            guard let id3Tag = try id3TagEditor.read(from: filePath) else { return }
            
            let albumArtist = (id3Tag.frames[.albumArtist] as? ID3FrameWithStringContent)?.content ?? "Unknown Artist"
            let album = (id3Tag.frames[.album] as? ID3FrameWithStringContent)?.content ?? "Unknown Album"
            let title = (id3Tag.frames[.title] as? ID3FrameWithStringContent)?.content ?? url.deletingPathExtension().lastPathComponent
            let trackPosition = (id3Tag.frames[.trackPosition] as? ID3FramePartOfTotal)?.part ?? 0
            let year: Int
            if let recordingYear = (id3Tag.frames[.recordingYear] as? ID3FrameWithStringContent)?.content {
                year = Int(recordingYear) ?? 0
            } else {
                year = 0
            }
            let genre = (id3Tag.frames[.genre] as? ID3FrameWithStringContent)?.content ?? "Unknown Genre"
            
            let asset = AVAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            
            let artwork = loadArtwork(from: id3Tag)
            
            let track = Track(url: url, title: title, trackNumber: trackPosition, duration: duration)
            
            updateLibrary(albumArtist: albumArtist, album: album, year: year, genre: genre, track: track, artwork: artwork)
        } catch {
            handleError(error)
        }
    }
    
    private func loadArtwork(from id3Tag: ID3Tag) -> Image? {
        if let attachedPictureFrame = id3Tag.frames[.attachedPicture(.frontCover)] as? ID3FrameAttachedPicture {
            let imageData = attachedPictureFrame.picture
            if let nsImage = NSImage(data: imageData) {
                return Image(nsImage: nsImage)
            }
        }
        return nil
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
            
            // Stop the current player before creating a new one
            player?.pause()
            player?.replaceCurrentItem(with: playerItem)
            
            guard let player = player else {
                player = AVPlayer(playerItem: playerItem)
                throw NSError(domain: "AudioPlayerError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create AVPlayer"])
            }
            
            player.volume = volume
            player.play()
            isPlaying = true
            
            setupTimeObserver()
            
            Task {
                do {
                    let duration = try await playerItem.asset.load(.duration)
                    await MainActor.run {
                        self.duration = duration.seconds
                    }
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
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }
    
    func seek(to time: TimeInterval) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }
    
    func setVolume(_ newVolume: Float) {
        volume = newVolume
        player?.volume = newVolume
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

    private func handleError(_ error: Error) {
        print("Error: \(error.localizedDescription)")
    }
    
    private var cancelBag = Set<AnyCancellable>()
    
    init() {
        setupDeinitHandler()
    }

    private func setupDeinitHandler() {
        // Use SwiftUI's scene phase or other methods to handle lifecycle changes
    }
    
    private func cleanup() {
        NotificationCenter.default.removeObserver(self)
        removeTimeObserver()
    }

    deinit {
        Task { @MainActor in
            cleanup()
        }
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

struct Album: Identifiable {
    let id = UUID()
    let title: String
    let year: Int
    let genre: String
    var tracks: [Track]
    let artwork: Image?
}

struct Track: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let trackNumber: Int
    let duration: TimeInterval
}
